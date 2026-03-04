/**
 * system-audio-capture — capture system audio via ScreenCaptureKit.
 *
 * Usage: system-audio-capture <output.wav>
 *
 * Records system audio (16 kHz mono 16-bit PCM WAV) until SIGINT or SIGTERM.
 * On signal, finalises the WAV header and exits 0.
 *
 * Requires macOS 13+ and Screen Recording permission.
 * The permission dialog appears automatically on first use.
 *
 * Exit codes:
 *   0 — success, WAV written
 *   1 — error (wrong args, permission denied, stream failure, …)
 */

import Foundation
import ScreenCaptureKit
import CoreMedia

// MARK: - WAV helpers

private let SAMPLE_RATE: Int    = 16_000
private let CHANNEL_COUNT: Int  = 1
private let BITS_PER_SAMPLE: Int = 16
private let BYTES_PER_SAMPLE: Int = BITS_PER_SAMPLE / 8

/// Write a 44-byte RIFF WAV header at the current file position.
/// Pass dataBytes == 0 for a placeholder; patch later by seeking to offset 0.
private func writeWavHeader(handle: FileHandle, dataBytes: UInt32) {
    var h = Data()
    func u32le(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
    func u16le(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }

    let byteRate   = UInt32(SAMPLE_RATE * CHANNEL_COUNT * BYTES_PER_SAMPLE)
    let blockAlign = UInt16(CHANNEL_COUNT * BYTES_PER_SAMPLE)
    let chunkSize  = UInt32(36) &+ dataBytes   // 36 = fmt chunk (24) + "data"+size (8)

    h += "RIFF".data(using: .ascii)!;  h += u32le(chunkSize)
    h += "WAVE".data(using: .ascii)!
    h += "fmt ".data(using: .ascii)!;  h += u32le(16)
    h += u16le(1)                                        // PCM
    h += u16le(UInt16(CHANNEL_COUNT))
    h += u32le(UInt32(SAMPLE_RATE))
    h += u32le(byteRate)
    h += u16le(blockAlign)
    h += u16le(UInt16(BITS_PER_SAMPLE))
    h += "data".data(using: .ascii)!;  h += u32le(dataBytes)

    handle.write(h)
}

// MARK: - Stream delegate

final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {

    private let handle: FileHandle
    private let writeQ = DispatchQueue(label: "wav-writer", qos: .userInteractive)
    private var pcmBytesWritten: UInt32 = 0
    private var finalised = false

    init(fileHandle: FileHandle) {
        self.handle = fileHandle
        super.init()
        writeWavHeader(handle: fileHandle, dataBytes: 0)  // placeholder
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Extract raw bytes from the CMBlockBuffer
        guard let blockBuf = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var lengthAtOffset = 0
        var totalLength    = 0
        var rawPtr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuf, atOffset: 0,
                                         lengthAtOffsetOut: &lengthAtOffset,
                                         totalLengthOut: &totalLength,
                                         dataPointerOut: &rawPtr) == kCMBlockBufferNoErr,
              let ptr = rawPtr, totalLength > 0 else { return }

        // SCStream delivers Float32 linear PCM; convert to Int16
        let floatCount = totalLength / MemoryLayout<Float32>.size
        let floats = UnsafeBufferPointer(
            start: UnsafeRawPointer(ptr).assumingMemoryBound(to: Float32.self),
            count: floatCount)

        var pcm16 = [Int16](repeating: 0, count: floatCount)
        for i in 0..<floatCount {
            let f = max(-1.0, min(1.0, floats[i]))
            pcm16[i] = Int16(f * 32_767.0)
        }

        let pcmData = pcm16.withUnsafeBufferPointer { Data(buffer: $0) }

        writeQ.async { [weak self] in
            guard let self, !self.finalised else { return }
            self.handle.write(pcmData)
            self.pcmBytesWritten &+= UInt32(pcmData.count)
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("[system-audio-capture] Stream stopped with error: \(error)\n", stderr)
    }

    // MARK: Shutdown

    /// Stop accepting buffers, patch the WAV header, close the file.
    func finalise() {
        writeQ.sync { self.finalised = true }
        let bytes = pcmBytesWritten
        handle.seek(toFileOffset: 0)
        writeWavHeader(handle: fileHandle, dataBytes: bytes)
        try? handle.close()
        fputs("[system-audio-capture] Wrote \(bytes) bytes of PCM audio.\n", stderr)
    }

    private var fileHandle: FileHandle { handle }
}

// MARK: - Entry point

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: system-audio-capture <output.wav>\n", stderr)
    exit(1)
}
let outputPath = CommandLine.arguments[1]

// Create/truncate the output file up front
FileManager.default.createFile(atPath: outputPath, contents: nil)
guard let fh = FileHandle(forWritingAtPath: outputPath) else {
    fputs("Cannot open for writing: \(outputPath)\n", stderr)
    exit(1)
}

let capture = AudioCapture(fileHandle: fh)
var activeStream: SCStream?

// --- Signal handling via DispatchSource (safe for async code) ---
signal(SIGINT,  SIG_IGN)   // prevent default handler; DispatchSource takes over
signal(SIGTERM, SIG_IGN)

func handleShutdown() {
    fputs("[system-audio-capture] Stopping...\n", stderr)
    Task {
        try? await activeStream?.stopCapture()
        capture.finalise()
        exit(0)
    }
}

let sigintSrc  = DispatchSource.makeSignalSource(signal: SIGINT,  queue: .main)
let sigtermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
for src in [sigintSrc, sigtermSrc] {
    src.setEventHandler { handleShutdown() }
    src.resume()
}

// --- Start SCStream ---
Task {
    do {
        let content: SCShareableContent = try await withCheckedThrowingContinuation { cont in
            SCShareableContent.getWithCompletionHandler { content, error in
                if let e = error        { cont.resume(throwing: e) }
                else if let c = content { cont.resume(returning: c) }
                else {
                    cont.resume(throwing: NSError(domain: "SCCapture", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No content returned"]))
                }
            }
        }

        guard let display = content.displays.first else {
            fputs("[system-audio-capture] No display found\n", stderr)
            exit(1)
        }

        // Capture all audio on this display; exclude our own process
        let filter = SCContentFilter(display: display,
                                     excludingApplications: [],
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio             = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate                = SAMPLE_RATE
        config.channelCount              = CHANNEL_COUNT
        // Minimise video load — we only want audio
        config.width                     = 2
        config.height                    = 2
        config.minimumFrameInterval      = CMTime(value: 1, timescale: 1)  // 1 fps

        let stream = SCStream(filter: filter, configuration: config, delegate: capture)
        try stream.addStreamOutput(capture, type: .audio, sampleHandlerQueue: nil)
        try await stream.startCapture()
        activeStream = stream

        fputs("[system-audio-capture] Recording to \(outputPath) — send SIGINT/SIGTERM to stop.\n", stderr)
    } catch {
        fputs("[system-audio-capture] Failed to start: \(error)\n", stderr)
        exit(1)
    }
}

RunLoop.main.run()  // drives async Tasks and DispatchSources indefinitely
