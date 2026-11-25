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
    @Published var preview: CGImage?
    @Published var updated: Date?
    @Published var positions = [CGFloat]()
    @Published var mode = "自动识别"
    private let renderer = CIContext()
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
        preview = nil
        updated = nil
        positions = []
        scene = "未知"
        session.pause()
        running = false
        status = "已停止"
        observation = "等待摄像头"
        speaker.stop()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard running else { return }
        stop()
        status = "摄像头已暂停，可重新开启"
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard running else { return }
        stop()
        status = "摄像头不可用，可重新开启"
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
        let depth = frame.sceneDepth
        analysis.async {
            let people = VNDetectHumanRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            do {
                let classifier = VNClassifyImageRequest()
                try handler.perform([people, classifier])
                let labels = classifier.results?.prefix(5).filter { $0.confidence >= 0.55 }.map(\.identifier) ?? []
                let centers = people.results?.filter { $0.confidence > 0.7 }.map { $0.boundingBox.midX } ?? []
                let image = CIImage(cvPixelBuffer: buffer).oriented(.right).transformed(by: CGAffineTransform(scaleX: 0.3, y: 0.3))
                let preview = self.renderer.createCGImage(image, from: image.extent)
                let person = people.results?.filter { $0.confidence > 0.7 }.max { $0.confidence < $1.confidence }
                var message = person.map {
                    let x = $0.boundingBox.midX
                    return (x < 0.33 ? "镜头左侧" : x > 0.67 ? "镜头右侧" : "画面中央") + "可能有人"
                } ?? "暂未识别到行人"
                if detail == "详细", let count = people.results?.filter({ $0.confidence > 0.7 }).count, count > 1 {
                    message += "。画面中共检测到约\(count)人"
                }
                let distance = depth?.centralDistance()
                let nearSurface = distance.map { $0 < 0.65 } ?? false
                if nearSurface { message += "。镜头中央可能有近距离表面" }
                if let distance, detail != "简洁" {
                    message += String(format: "。镜头中央表面约 %.1f 米", distance)
                }
                DispatchQueue.main.async {
                    self.analyzing = false
                    guard self.generation == token else { return }
                    let previousScene = self.scene
                    self.preview = preview
                    self.positions = centers
                    self.updated = Date()
                    let inferred = self.evidence.update(labels: labels)
                    self.scene = self.mode == "自动识别" ? inferred : self.mode
                    if self.scene != "未知", detail != "简洁" { message = (self.mode == "自动识别" ? "可能位于" : "手动模式：") + self.scene + "。" + message }
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

