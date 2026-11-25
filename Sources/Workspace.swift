import SwiftUI
import AVFoundation

let navy = Color(red: 23/255, green: 39/255, blue: 68/255)
struct PrimaryAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white).background(navy, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct Entry: Codable, Identifiable {
    let id: UUID
    let time: Date
    let scene: String
    let message: String
}

@main struct TOVAApp: App {
    var body: some Scene { WindowGroup { Workspace().tint(navy).preferredColorScheme(.light) } }
}

struct Workspace: View {
    @StateObject private var engine = Perception()
    @StateObject private var voice = Voice()
    @AppStorage("introduced") private var introduced = false
    @AppStorage("record") private var record = true
    @AppStorage("entries") private var entries = Data()
    @AppStorage("speech") private var speech = true
    @AppStorage("rate") private var rate = 0.5
    @AppStorage("volume") private var volume = 1.0
    @AppStorage("defaultLevel") private var defaultLevel = "标准"
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var paused = false
    let levels = ["简洁","标准","详细"]
    var history: [Entry] { (try? JSONDecoder().decode([Entry].self, from: entries)) ?? [] }
    func save(_ list: [Entry]) { if let data = try? JSONEncoder().encode(list) { entries = data } }
    func answer(_ question: String) {
        guard engine.running, let time = engine.updated, Date().timeIntervalSince(time) < 6 else {
            engine.say("暂时没有可用的实时画面"); return
        }
        switch question {
        case "附近有没有台阶": engine.say("当前无法可靠判断附近是否有台阶")
        case "左前方有什么", "右侧是什么":
            let left = question == "左前方有什么"
            let found = engine.positions.contains { left ? $0 < 0.33 : $0 > 0.67 }
            engine.say((left ? "镜头左侧" : "镜头右侧") + (found ? "可能有人" : "暂未识别到行人，其他物体情况未知"))
        default: engine.say(engine.observation)
        }
    }
    var body: some View {
        Group {
            if !introduced { Onboarding() } else {
                TabView(selection: $tab) {
                    NavigationStack { spatial }.tabItem { Label("空间", systemImage: "viewfinder") }.tag(0)
                    NavigationStack { records }.tabItem { Label("记录", systemImage: "clock") }.tag(1)
                    NavigationStack { settings }.tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
                }
            }
        }.onAppear {
            engine.level = defaultLevel
            voice.isSpeaking = { engine.speaker.speaking }
            voice.execute = { cmd in
                switch cmd {
                case .start: paused = false; engine.start()
                case .stop: paused = false; engine.stop(); engine.say("空间描述已关闭")
                case .level(let level): engine.level = level
                case .exit: voice.stop()
                case .ask(let text): answer(text)
                }
            }
        }.onChange(of: engine.observation) { _, value in
            if record && engine.running && engine.updated != nil {
                save(Array(([Entry(id: UUID(), time: Date(), scene: engine.scene, message: value)] + history).prefix(300)))
            }
        }.onChange(of: speech) { _, enabled in if !enabled { engine.speaker.stop() } }
        .onChange(of: phase) { _, value in if value == .background { voice.stop(); engine.stop(); paused = false } }
    }
    var spatial: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image("Wordmark").resizable().scaledToFit().frame(width: 98).accessibilityLabel("TOVA")
                    Spacer()
                    Button { tab = 2 } label: { Image(systemName: "gearshape").frame(width: 48,height: 48) }.accessibilityLabel("打开设置")
                }
                Text(paused ? "感知已暂停" : engine.status).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                if let frame = engine.preview {
                    Image(decorative: frame, scale: 1).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 200).clipped().accessibilityHidden(true)
                } else { FieldDiagram().frame(height: 170).accessibilityHidden(true) }
                Button(engine.running ? "关闭空间描述" : paused ? "恢复空间描述" : "开始空间描述") {
                    paused = false
                    if engine.running { engine.stop(); engine.say("空间描述已关闭") } else { engine.start() }
                }.buttonStyle(PrimaryAction())
                if engine.running || paused {
                    Button(paused ? "结束本次感知" : "暂停感知") {
                        paused = !paused
                        engine.stop()
                    }.frame(minHeight: 44)
                }
                HStack { Text("语音待命"); Spacer(); Button(voice.enabled ? "退出聆听" : "开始聆听") { toggleVoice() } }.frame(minHeight: 44)
                Text(voice.status).font(.subheadline)
                Divider()
                Picker("场景模式", selection: $engine.mode) { ForEach(["自动识别","室内","室外"], id: \.self) { Text($0) } }.pickerStyle(.menu)
                Text("描述等级").font(.headline)
                Picker("描述等级", selection: $engine.level) { ForEach(levels,id: \.self) { Text($0) } }.pickerStyle(.segmented)
                Divider()
                Text("最近描述").font(.title2.bold())
                if let time = engine.updated { Text("\(engine.scene) · \(time.formatted(date: .omitted, time: .standard))").font(.subheadline) }
                Text(engine.observation)
                OutputLabel(output: engine.speaker)
                if engine.running {
                    Menu("询问 TOVA") { ForEach(["前方有什么","左前方有什么","右侧是什么","附近有没有台阶","重复上一条描述"],id: \.self) { q in Button(q) { answer(q) } } }.frame(minHeight: 44)
                }
            }.foregroundStyle(navy).padding(24)
        }
    }
    func toggleVoice() { if voice.enabled { voice.stop() } else { voice.start() } }
    var records: some View {
        List {
            if history.isEmpty { ContentUnavailableView("还没有记录", systemImage: "clock", description: Text("开启空间描述后，可在这里回顾本机保存的感知结果。")) }
            ForEach(history) { entry in VStack(alignment: .leading, spacing: 8) {
                Text(entry.time.formatted() + " · " + entry.scene).font(.subheadline)
                Text(entry.message)
            } }.onDelete { offsets in var list = history; list.remove(atOffsets: offsets); save(list) }
        }.navigationTitle("记录").toolbar { if !history.isEmpty { EditButton() } }
    }
    var settings: some View {
        Form {
            Section("语音与音频") {
                Button(voice.enabled ? "退出语音待命" : "开启语音待命") { toggleVoice() }
                Toggle("语音播报", isOn: $speech)
                Text("语速"); Slider(value: $rate, in: 0.35...0.65).accessibilityLabel("语速")
                Text("播报音量"); Slider(value: $volume, in: 0...1).accessibilityLabel("播报音量")
                LabeledContent("交互语言", value: "普通话")
            }
            Section("空间感知") {
                Picker("默认描述等级", selection: $defaultLevel) { ForEach(levels,id: \.self) { Text($0) } }
                LabeledContent("摄像头", value: engine.status)
                Button("重新检查胸前佩戴") { engine.stop(); voice.stop(); introduced = false }
            }
            Section("隐私与无障碍") {
                Toggle("保存本地描述记录", isOn: $record)
                Text("图像与语音在设备上处理。记录仅保存描述文字和时间。文字大小与 VoiceOver 跟随系统。")
                Link("打开系统权限设置", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        }.navigationTitle("设置")
    }
}

struct OutputLabel: View {
    @ObservedObject var output: SpeechOutput
    var body: some View { Text(output.speaking ? "正在语音播报" : "播报待命").font(.subheadline) }
}

struct FieldDiagram: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func line(_ a: CGPoint, _ b: CGPoint) {
                var path = Path(); path.move(to: a); path.addLine(to: b)
                context.stroke(path, with: .color(navy.opacity(0.24)), lineWidth: 1)
            }
            for i in -5...5 {
                let n = CGFloat(i)
                line(CGPoint(x:w*(0.5+n*0.028),y:h*0.25),CGPoint(x:w*(0.5+n*0.094),y:h*0.88))
            }
            for t in [0.0,0.1,0.23,0.41,0.66,1.0] {
                let spread = w*(0.14+0.33*t), y = h*(0.25+0.63*t)
                line(CGPoint(x:w/2-spread,y:y),CGPoint(x:w/2+spread,y:y))
            }
        }.background(Color(red: 0.96, green: 0.97, blue: 0.98), in: RoundedRectangle(cornerRadius: 16))
    }
}
