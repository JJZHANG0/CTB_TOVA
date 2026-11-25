import SwiftUI
import ARKit
import Vision
import AVFoundation

final class Perception: NSObject, ObservableObject, ARSessionDelegate {
    @Published var status = "待开启"
    @Published var observation = "等待摄像头"
    @Published var running = false
    @Published var level = "标准"
    let session = ARSession()
    let speaker = AVSpeechSynthesizer()
    private let analysis = DispatchQueue(label: "tova.frames")
    private var lastFrame = -Double.infinity
    private var generation = UUID()

    func start() {
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
        session.pause()
        running = false
        status = "已停止"
        observation = "等待摄像头"
        speaker.stopSpeaking(at: .immediate)
    }

    func say(_ text: String) {
        let speech = AVSpeechUtterance(string: text)
        speech.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        speaker.speak(speech)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, frame.timestamp - lastFrame >= 2 else { return }
        lastFrame = frame.timestamp
        let token = generation
        let detail = level
        let buffer = frame.capturedImage
        let depth = frame.sceneDepth?.depthMap
        analysis.async {
            let people = VNDetectHumanRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            do {
                try handler.perform([people])
                let person = people.results?.filter { $0.confidence > 0.7 }.max { $0.confidence < $1.confidence }
                var message = person.map {
                    let x = $0.boundingBox.midX
                    return (x < 0.33 ? "镜头左侧" : x > 0.67 ? "镜头右侧" : "画面中央") + "可能有人"
                } ?? "暂未识别到行人"
                if let depth, detail != "简洁" {
                    CVPixelBufferLockBaseAddress(depth, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
                    if let base = CVPixelBufferGetBaseAddress(depth) {
                        let row = base.advanced(by: CVPixelBufferGetHeight(depth)/2 * CVPixelBufferGetBytesPerRow(depth))
                        let d = row.assumingMemoryBound(to: Float.self)[CVPixelBufferGetWidth(depth)/2]
                        if d.isFinite && d > 0.2 && d < 5 {
                            message += String(format: "。镜头中心测距约 %.1f 米", (d * 2).rounded()/2)
                        }
                    }
                }
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.status = "摄像头采集中"
                    if self.observation != message {
                        self.observation = message
                        if !self.speaker.isSpeaking { self.say(message) }
                    }
                }
            } catch {
                DispatchQueue.main.async { if self.generation == token { self.status = "画面分析失败" } }
            }
        }
    }
}

@main struct TOVAApp: App {
    @StateObject private var engine = Perception()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("实时空间描述") {
                        Text(engine.status).font(.headline)
                        Text(engine.observation).font(.title2)
                        Button(engine.running ? "关闭空间描述" : "开启空间描述") {
                            if engine.running { engine.stop() } else { engine.start() }
                        }.frame(minHeight: 48)
                    }
                    Section("播报") {
                        Picker("描述等级", selection: $engine.level) {
                            ForEach(["简洁", "标准"], id: \.self) { Text($0) }
                        }
                        Button("重听当前描述") { engine.say(engine.observation) }.disabled(!engine.running)
                    }
                    Text("请将手机竖直佩戴在胸前，后置镜头朝外。方向以画面为准。").font(.body)
                }.navigationTitle("TOVA")
            }.onChange(of: phase) { _, value in if value == .background { engine.stop() } }
        }
    }
}
