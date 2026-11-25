import AVFoundation

final class SpeechOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Priority: Int { case background, routine, change, urgent, requested }
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()
    private var active: AVSpeechUtterance?
    private var priority = Priority.background
    private var pending: (String, Priority)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func stop() {
        active = nil
        pending = nil
        speaking = false
        synth.stopSpeaking(at: .immediate)
    }

    func offer(_ text: String, priority next: Priority) {
        guard next != .background else { return }
        if active != nil {
            if next.rawValue <= priority.rawValue {
                if next.rawValue >= (pending?.1.rawValue ?? 0) { pending = (text, next) }
                return
            }
            stop()
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        active = utterance
        priority = next
        speaking = true
        synth.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard active === utterance else { return }
        active = nil
        speaking = false
        if let item = pending {
            pending = nil
            offer(item.0, priority: item.1)
        }
    }
}
