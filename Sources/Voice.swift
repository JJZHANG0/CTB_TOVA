import Speech
import AVFoundation

final class Voice: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "已关闭"
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let guide = GuideAudio()
    private var awaitingUntil = Date.distantPast
    private var needsWelcome = true
    private let audio = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var token = UUID()
    private var pendingWake: DispatchWorkItem?
    private var tapped = false
    var execute: ((Command) -> Void)?
    var isSpeaking: () -> Bool = { false }

    func stop(_ status: String = "已关闭") {
        token = UUID()
        guide.stop()
        awaitingUntil = .distantPast
        enabled = false
        releaseInput()
        self.status = status
    }

    private func releaseInput() {
        pendingWake?.cancel()
        pendingWake = nil
        task?.cancel()
        task = nil
        audio.stop()
        if tapped { audio.inputNode.removeTap(onBus: 0); tapped = false }
    }

    func start() {
        guard !enabled else { return }
        needsWelcome = true
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

    private func acknowledgeWake() {
        token = UUID()
        releaseInput()
        status = "请说指令"
        guide.play(7) {
            guard self.enabled else { return }
            self.awaitingUntil = Date().addingTimeInterval(8)
            self.listen()
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
        request.contextualStrings = Command.wakeWords + ["开启空间描述", "关闭空间描述"]
        guard recognizer.supportsOnDeviceRecognition else { stop("设备缺少离线普通话识别支持"); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let input = audio.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { stop("麦克风不可用"); return }
            if needsWelcome {
                needsWelcome = false
                status = "正在介绍唤醒方式"
                guide.play(6) { if self.enabled && self.token == current { self.listen() } }
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true
            try audio.start()
            status = "正在聆听"
            task = recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    guard self.token == current else { return }
                    self.pendingWake?.cancel()
                    if let result, !result.isFinal, !self.isSpeaking(),
                       Command.wakeWords.contains(Command.normalize(result.bestTranscription.formattedString)) {
                        let wake = DispatchWorkItem {
                            guard self.token == current, !self.isSpeaking() else { return }
                            self.acknowledgeWake()
                        }
                        self.pendingWake = wake
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: wake)
                    }
                    if let result, result.isFinal {
                        let words = Command.normalize(result.bestTranscription.formattedString)
                        self.token = UUID()
                        self.releaseInput()
                        if !self.isSpeaking() {
                            if Command.wakeWords.contains(words) {
                                self.acknowledgeWake()
                                return
                            }
                            let command = Command(words) ?? (Date() <= self.awaitingUntil ? Command("偷法" + words) : nil)
                            self.awaitingUntil = .distantPast
                            if let command { self.execute?(command) }
                        }
                        if self.enabled { self.listen() }
                    } else if let error = error as NSError? {
                        if error.code == 1110 || error.code == 203 {
                            self.token = UUID()
                            let retry = self.token
                            self.releaseInput()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                if self.enabled && self.token == retry { self.listen() }
                            }
                        } else { self.stop("聆听已中断，可重新开启") }
                    }
                }
            }
        } catch { stop("无法启动麦克风") }
    }
}
