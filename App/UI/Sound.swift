import AudioToolbox
import UIKit

/// 极轻量的音效与触感：只用系统声音，不塞音频文件，包体不变。
enum Sound {
    enum Kind {
        case none, draw, discard, redDiscard, peng, gang, win, join
    }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundOn") }
    }

    private static var lastPlayed = Date.distantPast

    static func play(_ kind: Kind) {
        guard kind != .none, enabled else { return }
        // 连点防炸：40ms 内重复触发的音效直接吞掉
        let now = Date()
        if now.timeIntervalSince(lastPlayed) < 0.04 { return }
        lastPlayed = now

        switch kind {
        case .draw: AudioServicesPlaySystemSound(1103)
        case .discard: AudioServicesPlaySystemSound(1104)
        case .redDiscard: AudioServicesPlaySystemSound(1053)
        case .peng: AudioServicesPlaySystemSound(1057)
        case .gang: AudioServicesPlaySystemSound(1054)
        case .win: AudioServicesPlaySystemSound(1025)
        case .join: AudioServicesPlaySystemSound(1105)
        case .none: break
        }

        switch kind {
        case .peng, .gang, .win:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .discard, .redDiscard:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default:
            break
        }
    }
}
