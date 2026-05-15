import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class NativeAudioRecorder {
    var onLevel: ((Float) -> Void)?
    var onRealtimePCM24kChunk: ((Data) -> Void)?

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var fileConverter: AVAudioConverter?
    private var realtimeConverter: AVAudioConverter?
    private var fileFormat: AVAudioFormat?
    private var realtimeFormat: AVAudioFormat?
    private var tapInstalled = false

    func start(outputURL: URL, inputDeviceUID: String?) throws {
        stop()
        try? FileManager.default.removeItem(at: outputURL)

        let inputNode = engine.inputNode
        if let inputDeviceUID,
           let deviceID = AudioDeviceManager.deviceID(for: inputDeviceUID) {
            try setInputDevice(deviceID, on: inputNode)
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "VoxFlow",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Formato de microfone invalido"]
            )
        }

        guard
            let fileFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
            let realtimeFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)
        else {
            throw NSError(
                domain: "VoxFlow",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Nao foi possivel criar formatos de audio"]
            )
        }

        self.fileFormat = fileFormat
        self.realtimeFormat = realtimeFormat
        outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        fileConverter = AVAudioConverter(from: inputFormat, to: fileFormat)
        realtimeConverter = AVAudioConverter(from: inputFormat, to: realtimeFormat)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        outputFile = nil
        fileConverter = nil
        realtimeConverter = nil
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        onLevel?(level(from: buffer))

        if let fileConverter,
           let fileFormat,
           let converted = convert(buffer, using: fileConverter, to: fileFormat) {
            try? outputFile?.write(from: converted)
        }

        if let realtimeConverter,
           let realtimeFormat,
           let converted = convert(buffer, using: realtimeConverter, to: realtimeFormat) {
            let data = pcmData(from: converted)
            if !data.isEmpty {
                onRealtimePCM24kChunk?(data)
            }
        }
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }

        var didProvideInput = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return nil }
        return converted
    }

    private func level(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }

        let samples = channels[0]
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = samples[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))
        return min(max(rms * 4, 0), 1)
    }

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else { return Data() }
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        return Data(bytes: bytes, count: Int(buffer.frameLength) * bytesPerFrame)
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on inputNode: AVAudioInputNode) throws {
        guard let audioUnit = inputNode.audioUnit else { return }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(
                domain: "VoxFlow",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Nao foi possivel seleccionar o microfone"]
            )
        }
    }
}
