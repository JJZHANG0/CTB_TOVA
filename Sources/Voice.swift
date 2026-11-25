import Speech
import AVFoundation

final class Voice: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "已关闭"
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audio = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var token = UUID()
    private var tapped = false
    var execute: ((Command) -> Void)?
    var isSpeaking: () -> Bool = { false }

    func stop(_ status: String = "已关闭") {
        token = UUID()
        enabled = false
        releaseInput()
        self.status = status
    }

    private func releaseInput() {
        task?.cancel()
        task = nil
        audio.stop()
        if tapped { audio.inputNode.removeTap(onBus: 0); tapped = false }
    }

    func start() {
        enabled = true
        status = "正在请求权限"
        let current = token
        SFSpeechRecognizer.requestAuthorization { auth in
            AVAudioApplication.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    guard self.token == current else { return }
                    guard auth == .authorized && allowed else {
                        self.stop("请在设置中允许麦克风和语音识别")
                        return
                    }
                    self.listen()
                }
            }
        }
    }

    private func listen() {
        guard enabled, let recognizer, recognizer.isAvailable else {
            stop("普通话识别暂不可用")
            return
        }
        token = UUID()
        let current = token
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        guard recognizer.supportsOnDeviceRecognition else { stop("设备缺少离线普通话识别支持"); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let input = audio.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { stop("麦克风不可用"); return }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true
            try audio.start()
            status = "正在聆听"
            task = recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    guard self.token == current else { return }
                    if let result, result.isFinal {
                        let command = Command(result.bestTranscription.formattedString)
                        self.token = UUID()
                        self.releaseInput()
                        if let command, !self.isSpeaking() { self.execute?(command) }
                        if self.enabled { self.listen() }
                    } else if error != nil { self.stop("聆听已中断，可重新开启") }
                }
            }
        } catch { stop("无法启动麦克风") }
    }
}
