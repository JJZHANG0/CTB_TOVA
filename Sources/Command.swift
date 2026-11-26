import Foundation

enum Command: Equatable {
    case start, stop, exit, level(String), ask(String)

    static let wakeWords = ["偷法", "托法", "他法", "脱法", "拖法", "头法", "托发", "tova", "托瓦", "托娃"]
    static func normalize(_ transcription: String) -> String {
        transcription.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).joined()
    }

    init?(_ transcription: String) {
        let words = Self.normalize(transcription)
        guard let wake = Self.wakeWords.first(where: { words.hasPrefix($0) }) else { return nil }
        switch words.dropFirst(wake.count) {
        case "执行空间描述", "请你执行空间描述", "开启空间描述", "开始空间描述": self = .start
        case "关闭空间描述": self = .stop
        case "退出语音待命": self = .exit
        case "切换简洁描述": self = .level("简洁")
        case "切换标准描述": self = .level("标准")
        case "切换详细描述": self = .level("详细")
        case let query where ["前方有什么", "左前方有什么", "右侧是什么", "附近有没有台阶", "详细描述一下这个空间", "重复上一条描述"].contains(String(query)): self = .ask(String(query))
        default: return nil
        }
    }
}
