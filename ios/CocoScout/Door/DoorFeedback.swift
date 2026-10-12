import AVFoundation
import UIKit

/// The sound and buzz for each result, the same as the door page makes in a
/// browser (door_controller.js feedback): a short rising chirp when someone's
/// in, a low buzz for anything else, so the door never has to read the screen.
@MainActor
final class DoorFeedback {
    private let chirp = DoorFeedback.tone(frequency: 880, seconds: 0.15, square: false)
    private let buzz = DoorFeedback.tone(frequency: 220, seconds: 0.4, square: true)
    private let haptics = UINotificationFeedbackGenerator()

    init() {
        // Plays over whatever else is on and stays quiet on silent; the buzz
        // in the hand still comes.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        haptics.prepare()
    }

    func play(_ tone: DoorResult.Tone) {
        let player = tone == .admitted ? chirp : buzz
        player?.currentTime = 0
        player?.play()
        switch tone {
        case .admitted: haptics.notificationOccurred(.success)
        case .already: haptics.notificationOccurred(.warning)
        case .error: haptics.notificationOccurred(.error)
        }
        haptics.prepare()
    }

    /// A tone made on the spot (16-bit mono WAV), with a few milliseconds of
    /// fade at each end so it doesn't click.
    private static func tone(frequency: Double, seconds: Double, square: Bool) -> AVAudioPlayer? {
        let rate = 44_100
        let count = Int(Double(rate) * seconds)
        let fade = Double(rate) * 0.005
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            var value = sin(2 * Double.pi * frequency * Double(index) / Double(rate))
            if square { value = value >= 0 ? 1 : -1 }
            let edge = min(1, min(Double(index), Double(count - index)) / fade)
            samples[index] = Int16(value * 0.3 * edge * Double(Int16.max))
        }

        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        let bytes = UInt32(count * 2)
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + bytes)
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        wav.append(contentsOf: Array("data".utf8))
        append(bytes)
        samples.forEach { append($0) }

        let player = try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
        player?.prepareToPlay()
        return player
    }
}
