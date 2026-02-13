import CoreAudio

// Check ALL input devices. Print the active device's name, or "inactive" if none.
// Meeting apps may use iPhone Continuity mic, AirPods, etc.

func getDeviceName(_ deviceID: AudioDeviceID) -> String {
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
    return name as String
}

var propSize = UInt32(0)
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize)
let deviceCount = Int(propSize) / MemoryLayout<AudioDeviceID>.size
var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize, &devices)

for device in devices {
    var inputSize = UInt32(0)
    var inputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyDataSize(device, &inputAddress, 0, nil, &inputSize)
    guard inputSize > 0 else { continue }

    let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
    defer { bufferListPtr.deallocate() }
    AudioObjectGetPropertyData(device, &inputAddress, 0, nil, &inputSize, bufferListPtr)
    guard bufferListPtr.pointee.mBuffers.mNumberChannels > 0 else { continue }

    var isRunning = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var runAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyData(device, &runAddress, 0, nil, &size, &isRunning)

    if isRunning == 1 {
        let name = getDeviceName(device)
        // Skip virtual audio devices used for loopback capture
        if name.hasPrefix("BlackHole") { continue }
        print(name)
        exit(0)
    }
}

print("inactive")
