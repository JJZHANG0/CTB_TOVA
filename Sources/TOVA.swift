import SwiftUI
import ARKit
import Vision
import AVFoundation

final class Perception: NSObject, ObservableObject, ARSessionDelegate {
    @Published var status = "待开启"
    @Published var observation = "等待摄像头"
    @Published var running = false
    @Published var level = "标准"
    @Published var scene = "未知"
    private var evidence = SceneEvidence()
    private var analyzing = false
    let session = ARSession()
    let speaker = SpeechOutput()
    private let analysis = DispatchQueue(label: "tova.frames")
    private var lastFrame = -Double.infinity
    private var generation = UUID()

    func start() {
        guard !running else { return }
        running = true
        status = "正在初始化"
        let token = UUID()
        generation = token
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                guard allowed, ARWorldTrackingConfiguration.isSupported else {
                    self.stop()
                    self.status = allowed ? "设备不支持空间跟踪" : "请在设置中允许摄像头访问"
                    return
                }
                let config = ARWorldTrackingConfiguration()
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.insert(.sceneDepth)
                }
                self.session.delegate = self
                self.session.run(config)
                self.say("空间描述已开启，正在分析周围环境。")
            }
        }
    }

    func stop() {
        generation = UUID()
        evidence = SceneEvidence()
        scene = "未知"
        session.pause()
        running = false
        status = "已停止"
        observation = "等待摄像头"
        speaker.stop()
    }

    func say(_ text: String) {
        speaker.offer(text, priority: .requested)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, !analyzing, frame.timestamp - lastFrame >= 2 else { return }
        analyzing = true
        lastFrame = frame.timestamp
        let token = generation
        let detail = level
        let buffer = frame.capturedImage
        let depth = frame.sceneDepth?.depthMap
        analysis.async {
            let people = VNDetectHumanRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            do {
                let classifier = VNClassifyImageRequest()
                try handler.perform([people, classifier])
                let labels = classifier.results?.prefix(5).filter { $0.confidence >= 0.55 }.map(\.identifier) ?? []
                let person = people.results?.filter { $0.confidence > 0.7 }.max { $0.confidence < $1.confidence }
                var message = person.map {
                    let x = $0.boundingBox.midX
                    return (x < 0.33 ? "镜头左侧" : x > 0.67 ? "镜头右侧" : "画面中央") + "可能有人"
                } ?? "暂未识别到行人"
                if detail == "详细", let count = people.results?.filter({ $0.confidence > 0.7 }).count, count > 1 {
                    message += "。画面中共检测到约\(count)人"
                }
                var nearSurface = false
                if let depth {
                    CVPixelBufferLockBaseAddress(depth, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
                    if let base = CVPixelBufferGetBaseAddress(depth) {
                        let row = base.advanced(by: CVPixelBufferGetHeight(depth)/2 * CVPixelBufferGetBytesPerRow(depth))
                        let d = row.assumingMemoryBound(to: Float.self)[CVPixelBufferGetWidth(depth)/2]
                        if d.isFinite && d > 0.2 && d < 5 {
                            nearSurface = d < 0.65
                            if nearSurface { message += "。镜头中央可能有近距离表面" }
                            if detail != "简洁" { message += String(format: "。镜头中心测距约 %.1f 米", (d * 2).rounded()/2) }
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.analyzing = false
                    guard self.generation == token else { return }
                    let previousScene = self.scene
                    self.scene = self.evidence.update(labels: labels)
                    if self.scene != "未知", detail != "简洁" { message = "可能位于" + self.scene + "。" + message }
                    self.status = "摄像头采集中"
                    if self.observation != message {
                        self.observation = message
                        self.speaker.offer(message, priority: nearSurface ? .urgent : previousScene != self.scene ? .change : .routine)
                    }
                }
            } catch {
                DispatchQueue.main.async { self.analyzing = false; if self.generation == token { self.status = "画面分析失败" } }
            }
        }
    }
}

@main struct TOVAApp: App {
    @ScaledMetric(relativeTo: .body) private var touchHeight = 48.0
    @StateObject private var engine = Perception()
    @StateObject private var voice = Voice()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("实时空间描述") {
                        Text(engine.status).font(.headline)
                        LabeledContent("场景", value: engine.scene)
                        Text(engine.observation).font(.title2)
                        Button(engine.running ? "关闭空间描述" : "开启空间描述") {
                            if engine.running { engine.stop() } else { engine.start() }
                        }.frame(minHeight: touchHeight)
                            .accessibilityHint("控制后置摄像头和环境播报")
                    }
                    Section("语音待命") {
                        Text(voice.status)
                        Button(voice.enabled ? "退出语音待命" : "开启语音待命") {
                            if voice.enabled { voice.stop() } else { voice.start() }
                        }.frame(minHeight: touchHeight)
                        Text("可以说「TOVA，开启空间描述」。").font(.footnote)
                    }
                    Section("播报") {
                        SpeechStatus(output: engine.speaker)
                        Picker("描述等级", selection: $engine.level) {
                            ForEach(["简洁", "标准", "详细"], id: \.self) { Text($0) }
                        }
                        Button("重听当前描述") { engine.say(engine.observation) }.disabled(!engine.running)
                    }
                    Text("请将手机竖直佩戴在胸前，后置镜头朝外。方向以画面为准。").font(.body)
                }.navigationTitle("TOVA")
            }.onAppear {
                voice.isSpeaking = { engine.speaker.speaking }
                voice.execute = { command in
                    switch command {
                    case .start: engine.start()
                    case .stop: engine.stop(); engine.say("空间描述已关闭")
                    case .level(let level): engine.level = level
                    case .exit: voice.stop()
                    }
                }
            }.onChange(of: phase) { _, value in if value == .background { voice.stop(); engine.stop() } }
        }
    }
}

private struct SpeechStatus: View {
    @ObservedObject var output: SpeechOutput
    var body: some View { LabeledContent("语音输出", value: output.speaking ? "正在播报" : "待命") }
}
