import SwiftUI
import AVFoundation
import Speech

struct Onboarding: View {
    @AppStorage("introduced") var introduced = false
    @StateObject private var guide = GuideAudio()
    @Environment(\.scenePhase) private var phase
    @AccessibilityFocusState private var actionFocused: Bool
    @State private var step = 0
    @State private var requesting = false
    let titles = ["让你听见空间，理解周围。", "从胸前的视角感知", "允许摄像头访问", "用声音控制 TOVA", "授权普通话识别", "确认佩戴位置"]
    let details = ["用声音了解周围的方向、距离和变化。", "后置镜头观察环境，设备在本地分析画面，重要变化通过语音提醒。", "开始空间描述时使用后置镜头。你也可以稍后在系统设置中授权。", "麦克风用于前台语音待命。也可以通过按钮控制感知。", "命令在设备上识别，需要系统支持离线普通话。", "将手机竖直固定在胸前，后置镜头朝外。确认左右方向，避免镜头朝地或被衣物遮住。"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image("Wordmark").resizable().scaledToFit().frame(width: 124).accessibilityLabel("TOVA")
            Spacer()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("初次使用 · \(step + 1) / 6").font(.subheadline)
                    Text(titles[step]).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(details[step]).font(.title3)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 350)
            Spacer()
            Button("重听本步说明") { guide.play(step) }.frame(minHeight: 44)
            Button(step == 5 ? "已确认，进入空间" : (2...4).contains(step) ? "请求权限" : "继续") {
                guide.stop()
                if (2...4).contains(step) {
                    requesting = true
                    Task {
                        switch step {
                        case 2: _ = await AVCaptureDevice.requestAccess(for: .video)
                        case 3: _ = await AVAudioApplication.requestRecordPermission()
                        default: _ = await withCheckedContinuation { continuation in
                            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0.rawValue) }
                        }
                        }
                        requesting = false
                        step += 1
                    }
                } else if step == 5 { introduced = true } else { step += 1 }
            }.buttonStyle(PrimaryAction()).disabled(requesting).accessibilityFocused($actionFocused)
            if (2...4).contains(step) { Button("稍后设置") { step += 1 }.disabled(requesting).frame(minHeight: 44) }
        }.padding(24)
        .onAppear { guide.play(step) }
        .onChange(of: step) { _, next in actionFocused = true; guide.play(next) }
        .onChange(of: phase) { _, value in if value == .background { guide.stop() } }
        .onDisappear { guide.stop() }
    }
}
