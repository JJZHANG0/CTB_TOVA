import Foundation

enum Command: Equatable {
    case start, stop, exit, level(String)

    init?(_ transcription: String) {
        let words = transcription.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).joined()
        guard let wake = ["tova", "托瓦", "托娃"].first(where: { words.hasPrefix($0) }) else { return nil }
        switch words.dropFirst(wake.count) {
        case "执行空间描述", "请你执行空间描述", "开启空间描述": self = .start
        case "关闭空间描述": self = .stop
        case "退出语音待命": self = .exit
        case "切换简洁描述": self = .level("简洁")
        case "切换标准描述": self = .level("标准")
        case "切换详细描述": self = .level("详细")
        default: return nil
        }
    }
}
