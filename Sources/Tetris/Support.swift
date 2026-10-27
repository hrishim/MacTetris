import Foundation
import AVFoundation

// MARK: - High score persistence

struct ScoreEntry: Codable, Equatable {
    let score: Int
    let lines: Int
    let date: Date
}

enum HighScores {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tetris", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scores.json")
    }

    static func load() -> [ScoreEntry] {
        guard let data = try? Data(contentsOf: url),
              let e = try? JSONDecoder().decode([ScoreEntry].self, from: data) else { return [] }
        return e
    }

    /// Records a finished game; returns true when it beat the previous best.
    @discardableResult
    static func record(score: Int, lines: Int) -> Bool {
        var e = load()
        let prevBest = e.first?.score ?? 0
        let isBest = score > 0 && score > prevBest
        e.append(ScoreEntry(score: score, lines: lines, date: Date()))
        e.sort { $0.score != $1.score ? $0.score > $1.score : $0.date < $1.date }
        e = Array(e.prefix(10))
        if let d = try? JSONEncoder().encode(e) { try? d.write(to: url) }
        return isBest
    }

    static func best() -> Int { load().first?.score ?? 0 }
    static func top(_ n: Int) -> [ScoreEntry] { Array(load().prefix(n)) }
}

// MARK: - Procedural sound effects (synthesized WAVs, no assets)

final class SoundEngine {
    static let shared = SoundEngine()
    static let sampleRate = 44100.0

    private var players: [String: AVAudioPlayer] = [:]
    private(set) var muted: Bool
    private var vol: Float

    private init() {
        let d = UserDefaults.standard
        muted = d.bool(forKey: "tetris.muted")
        vol = d.object(forKey: "tetris.volume") as? Float ?? 0.5
        buildAll()
    }

    func toggleMute() -> Bool {
        muted.toggle()
        UserDefaults.standard.set(muted, forKey: "tetris.muted")
        return muted
    }

    func play(_ name: String) {
        guard !muted, let p = players[name] else { return }
        p.currentTime = 0
        p.play()
    }

    // MARK: synthesis

    private func tone(f0: Double, f1: Double, dur: Double, gain: Double, decay: Double = 8.0) -> [Float] {
        let n = Int(dur * Self.sampleRate)
        var out = [Float](repeating: 0, count: max(n, 1))
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let f = f0 + (f1 - f0) * t
            phase += 2.0 * Double.pi * f / Self.sampleRate
            let env = exp(-decay * t) * (1.0 - t)
            out[i] = Float(sin(phase) * env * gain)
        }
        if n > 40 { // fade-out tail to avoid click
            for i in 0..<40 { out[n - 1 - i] *= Float(i) / 40.0 }
        }
        return out
    }

    private func concat(_ parts: [[Float]]) -> [Float] {
        parts.reduce(into: [Float](repeating: 0, count: 0)) { $0 + $1 }
    }

    private func buildAll() {
        let sfx: [String: [Float]] = [
            "move":    tone(f0: 700, f1: 700, dur: 0.012, gain: 0.10),
            "rotate":  tone(f0: 920, f1: 1100, dur: 0.030, gain: 0.12),
            "hold":    tone(f0: 540, f1: 660, dur: 0.045, gain: 0.14),
            "drop":    concat([tone(f0: 300, f1: 140, dur: 0.05, gain: 0.20, decay: 12),
                               tone(f0: 90,  f1: 60,  dur: 0.04, gain: 0.25, decay: 20)]),
            "lock":    tone(f0: 150, f1: 110, dur: 0.045, gain: 0.16, decay: 16),
            "clear1":  tone(f0: 660, f1: 880, dur: 0.07, gain: 0.18),
            "clear2":  concat([tone(f0: 660, f1: 660, dur: 0.05, gain: 0.18),
                               tone(f0: 880, f1: 880, dur: 0.06, gain: 0.18)]),
            "clear3":  concat([tone(f0: 660, f1: 660, dur: 0.04, gain: 0.18),
                               tone(f0: 830, f1: 830, dur: 0.04, gain: 0.18),
                               tone(f0: 1046, f1: 1046, dur: 0.06, gain: 0.18)]),
            "tetris":  concat([523.25, 659.25, 783.99, 1046.5].map {
                                   tone(f0: $0, f1: $0, dur: 0.07, gain: 0.20, decay: 5) }),
            "level":   concat([440.0, 554.37, 659.25].map {
                                   tone(f0: $0, f1: $0, dur: 0.06, gain: 0.16, decay: 6) }),
            "over":    tone(f0: 420, f1: 100, dur: 0.45, gain: 0.20, decay: 4),
        ]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tetris_sfx", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, samples) in sfx {
            let url = dir.appendingPathComponent("\(name).wav")
            if !FileManager.default.fileExists(atPath: url.path) || true {
                writeWAV(samples, to: url)
            }
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.volume = vol
                p.prepareToPlay()
                players[name] = p
            }
        }
    }

    private func writeWAV(_ samples: [Float], to url: URL) {
        let n = samples.count
        let dataRate = UInt32(Self.sampleRate * 2)
        var d = Data()
        func str(_ s: String) { d.append(Data(s.utf8)) }
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        str("RIFF"); u32(36 + UInt32(n * 2)); str("WAVEfmt ")
        u32(16); u16(1); u16(1); u32(UInt32(Self.sampleRate)); u32(dataRate); u16(2); u16(16)
        str("data"); u32(UInt32(n * 2))
        for s in samples {
            let v = max(-1.0, min(1.0, Double(s)))
            var q = Int16(v * 32767); var x = q.littleEndian
            d.append(Data(bytes: &x, count: 2))
        }
        try? d.write(to: url)
    }
}
