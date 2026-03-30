import Foundation
import ScreenCaptureKit
import CoreMedia

// MARK: - Constants

private let SAMPLE_RATE: Int      = 16_000
private let CHANNEL_COUNT: Int    = 1
private let BITS_PER_SAMPLE: Int  = 16
private let BYTES_PER_SAMPLE: Int = BITS_PER_SAMPLE / 8

// MARK: - WAV helpers

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
    h += u16le(1)                                         // PCM
    h += u16le(UInt16(CHANNEL_COUNT))
    h += u32le(UInt32(SAMPLE_RATE))
    h += u32le(byteRate)
    h += u16le(blockAlign)
    h += u16le(UInt16(BITS_PER_SAMPLE))
    h += "data".data(using: .ascii)!;  h += u32le(dataBytes)

    handle.write(h)
}

// MARK: - Audio capture delegate

private final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let handle: FileHandle
    private let writeQ = DispatchQueue(label: "speaker-wav-writer", qos: .userInteractive)
    private var pcmBytesWritten: UInt32 = 0
    private var finalised = false

    init(fileHandle: FileHandle) {
        self.handle = fileHandle
        super.init()
        writeWavHeader(handle: fileHandle, dataBytes: 0)  // placeholder header
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
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

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[SpeakerCapture] Stream stopped with error: \(error)")
    }

    func finalise() {
        writeQ.sync { self.finalised = true }
        let bytes = pcmBytesWritten
        handle.seek(toFileOffset: 0)
        writeWavHeader(handle: handle, dataBytes: bytes)
        try? handle.close()
        print("[SpeakerCapture] Wrote \(bytes) bytes of PCM audio.")
    }
}

// MARK: - Manager

/// Captures system audio in-process using ScreenCaptureKit.
///
/// Running in-process means the TCC Screen Recording permission granted to this
/// app applies directly — no separate executable, no separate TCC entry.
actor SpeakerCaptureManager {
    private var stream: SCStream?
    private var capture: AudioCapture?

    func start(outputPath: String) async {
        await stop()  // clean up any previous capture

        FileManager.default.createFile(atPath: outputPath, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: outputPath) else {
            print("[SpeakerCapture] Cannot open for writing: \(outputPath)")
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                print("[SpeakerCapture] No display found")
                return
            }

            let filter = SCContentFilter(display: display,
                                         excludingApplications: [],
                                         exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio               = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate                  = SAMPLE_RATE
            config.channelCount                = CHANNEL_COUNT
            // Minimise video overhead — we only want audio
            config.width                       = 2
            config.height                      = 2
            config.minimumFrameInterval        = CMTime(value: 1, timescale: 1)  // 1 fps

            let audioCap = AudioCapture(fileHandle: fh)
            let scStream = SCStream(filter: filter, configuration: config, delegate: audioCap)
            try scStream.addStreamOutput(audioCap, type: .audio, sampleHandlerQueue: nil)
            try await scStream.startCapture()

            self.stream  = scStream
            self.capture = audioCap
            print("[SpeakerCapture] Recording to \(outputPath)")
        } catch {
            print("[SpeakerCapture] Failed to start: \(error)")
        }
    }

    func stop() async {
        guard let s = stream else { return }
        try? await s.stopCapture()
        capture?.finalise()
        stream  = nil
        capture = nil
    }
}
