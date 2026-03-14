import AVFoundation
import Foundation

// MARK: - Glitch Sound Style

enum GlitchSoundStyle: String, CaseIterable {
    case off           = "off"
    case staticNoise   = "static"
    case digitalGlitch = "digital"
    case electricBuzz  = "buzz"
    case signalLost    = "signal"

    var displayName: String {
        switch self {
        case .off:           return "Off"
        case .staticNoise:   return "Static"
        case .digitalGlitch: return "Digital"
        case .electricBuzz:  return "Buzz"
        case .signalLost:    return "Signal Lost"
        }
    }

    var icon: String {
        switch self {
        case .off:           return "speaker.slash"
        case .staticNoise:   return "tv.slash"
        case .digitalGlitch: return "waveform.path.ecg"
        case .electricBuzz:  return "bolt.fill"
        case .signalLost:    return "antenna.radiowaves.left.and.right.slash"
        }
    }
}

// MARK: - Glitch Sound Player

final class GlitchSoundPlayer {
    static let shared = GlitchSoundPlayer()

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44100

    private init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        try? engine.start()
    }

    // MARK: - Public API

    func play(style: GlitchSoundStyle) {
        guard style != .off else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            self.stop()
            guard let buffer = self.makeBuffer(style: style) else { return }
            if !self.engine.isRunning { try? self.engine.start() }
            self.playerNode.scheduleBuffer(buffer, completionHandler: nil)
            self.playerNode.play()
        }
    }

    func stop() {
        playerNode.stop()
    }

    // MARK: - Buffer factory

    private func makeBuffer(style: GlitchSoundStyle) -> AVAudioPCMBuffer? {
        switch style {
        case .off:           return nil
        case .staticNoise:   return makeStaticNoise()
        case .digitalGlitch: return makeDigitalGlitch()
        case .electricBuzz:  return makeElectricBuzz()
        case .signalLost:    return makeSignalLost()
        }
    }

    // MARK: - Static noise (TV/radio noise with amplitude surges)

    private func makeStaticNoise() -> AVAudioPCMBuffer? {
        let duration = 2.8
        return generateBuffer(duration: duration) { sample, total in
            let t = Double(sample) / Double(total)
            // Base white noise
            var s = Float.random(in: -0.35...0.35)
            // Amplitude surges at start and random spikes
            let envStart = min(1.0, Double(sample) / (sampleRate * 0.05))
            let envEnd   = max(0.0, 1.0 - (t - 0.85) / 0.15)
            let env = Float(envStart * (t < 0.85 ? 1.0 : envEnd))
            // Random amplitude pops
            if Float.random(in: 0...1) < 0.003 {
                s = Float.random(in: -0.75...0.75)
            }
            return s * env
        }
    }

    // MARK: - Digital glitch (fragmented tones + silence cuts + noise bursts)

    private func makeDigitalGlitch() -> AVAudioPCMBuffer? {
        let duration = 2.8
        // Pre-generate segment plan: alternating noisy/silent/tone segments
        let segmentLength = Int(sampleRate * 0.04)  // ~40ms chunks
        var plan: [SegmentType] = []
        var filled = 0
        let total  = Int(sampleRate * duration)
        while filled < total {
            let t: SegmentType = [.tone, .noise, .silence, .noise, .tone].randomElement()!
            plan.append(t)
            filled += segmentLength
        }

        var freqs: [Double] = [220, 440, 880, 55, 1760, 110]

        return generateBuffer(duration: duration) { sample, totalSamples in
            let segIdx  = sample / segmentLength
            guard segIdx < plan.count else { return 0 }
            let type    = plan[segIdx]
            let t       = Double(sample) / Double(totalSamples)
            let envEnd  = Float(max(0.0, 1.0 - max(0, t - 0.82) / 0.18))

            switch type {
            case .silence:
                return 0
            case .noise:
                return Float.random(in: -0.4...0.4) * envEnd
            case .tone:
                let freq = freqs[segIdx % freqs.count]
                let phase = Double(sample) * 2.0 * .pi * freq / sampleRate
                // Sawtooth
                let saw = Float((phase / .pi).truncatingRemainder(dividingBy: 2.0) - 1.0)
                // Mix with noise for grit
                return (saw * 0.45 + Float.random(in: -0.15...0.15)) * envEnd
            }
        }
    }

    // MARK: - Electric buzz (sawtooth ~80Hz + noise, amplitude spikes)

    private func makeElectricBuzz() -> AVAudioPCMBuffer? {
        let duration = 2.5
        let freq = 78.0

        return generateBuffer(duration: duration) { sample, totalSamples in
            let t = Double(sample) / Double(totalSamples)
            let phase = Double(sample) * 2.0 * .pi * freq / sampleRate
            // Sawtooth wave
            let saw = Float((phase / .pi).truncatingRemainder(dividingBy: 2.0) - 1.0)
            // Noise layer for grittiness
            let noise = Float.random(in: -0.18...0.18)
            // Amplitude modulation: irregular pulsing
            let mod = Float(0.6 + 0.4 * sin(Double(sample) * 2.0 * .pi * 7.3 / sampleRate))
            // Envelope: punchy start, hold, fade end
            let envStart = Float(min(1.0, Double(sample) / (sampleRate * 0.02)))
            let envEnd   = Float(max(0.0, 1.0 - max(0, t - 0.80) / 0.20))
            // Occasional hard cuts
            let cut: Float = (sample % Int(sampleRate * 0.07) < Int(sampleRate * 0.005)) ? 0 : 1
            return (saw * 0.55 + noise) * mod * envStart * envEnd * cut
        }
    }

    // MARK: - Signal Lost (descending tone sweep + rising static)

    private func makeSignalLost() -> AVAudioPCMBuffer? {
        let duration = 3.0
        let freqStart = 1200.0
        let freqEnd   = 80.0

        var phase = 0.0
        return generateBuffer(duration: duration) { sample, totalSamples in
            let t = Double(sample) / Double(totalSamples)
            // Exponential frequency sweep downward
            let freq = freqStart * pow(freqEnd / freqStart, t)
            phase += 2.0 * .pi * freq / sampleRate
            let tone = Float(sin(phase))

            // Rising static layer as signal degrades
            let noiseAmt = Float(t * t * 0.5)
            let noise    = Float.random(in: -1...1) * noiseAmt

            // Tone fades as noise rises
            let toneFade = Float(max(0, 1.0 - t * 1.1))
            // Stutter: brief signal dropouts
            let dropout: Float = (Int(t * sampleRate * 3) % 17 == 0) ? 0 : 1

            let envEnd = Float(max(0.0, 1.0 - max(0, t - 0.88) / 0.12))
            return (tone * toneFade * 0.5 + noise) * envEnd * dropout
        }
    }

    // MARK: - PCM buffer generator helper

    private func generateBuffer(duration: Double,
                                 sample: (Int, Int) -> Float) -> AVAudioPCMBuffer? {
        let format      = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount  = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let data = buffer.floatChannelData?[0] else { return nil }
        let total = Int(frameCount)
        for i in 0..<total {
            data[i] = sample(i, total)
        }
        return buffer
    }

    private enum SegmentType { case tone, noise, silence }
}
