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
                VStack(alignment: .leading, spacing: 8) {
                    Text("环境感知").font(.largeTitle.bold())
                    Text("听见镜头前的方向与距离。").font(.body).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "viewfinder").font(.title2).accessibilityHidden(true)
                        Spacer()
                        Text(paused ? "已暂停" : engine.status).font(.subheadline.weight(.medium))
                    }.foregroundStyle(.white)
                    if let frame = engine.preview {
                        Image(decorative: frame, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 180).accessibilityHidden(true)
                    } else { FieldDiagram().frame(height: 102).accessibilityHidden(true) }
                    Button {
                        paused = false
                        if engine.running { engine.stop(); engine.say("空间描述已关闭") } else { engine.start() }
                    } label: {
                        HStack {
                            Image(systemName: engine.running ? "stop.fill" : "power")
                            Text(engine.running ? "关闭空间描述" : paused ? "恢复空间描述" : "开始空间描述").font(.headline)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.padding(.horizontal, 18).frame(minHeight: 52)
                        .foregroundStyle(navy).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain)
                }.padding(20).background(navy, in: RoundedRectangle(cornerRadius: 24))
                if engine.running || paused {
                    Button(paused ? "结束本次感知" : "暂停感知") {
                        paused = !paused
                        engine.stop()
                    }.frame(minHeight: 44)
                }
                Button { toggleVoice() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: voice.enabled ? "waveform" : "mic").font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(voice.enabled ? "退出语音待命" : "开启语音待命").font(.headline)
                            Text(voice.enabled ? voice.status : "说「托瓦，开启空间描述」").font(.subheadline)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote)
                    }.padding(16).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                Text("感知概况").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: 12) {
                    SummaryTile(icon: "square.3.layers.3d", label: "当前环境", value: engine.updated == nil ? "等待感知" : engine.scene)
                    SummaryTile(icon: "person.crop.rectangle", label: "画面内行人", value: engine.updated == nil ? "暂无结果" : "约 " + String(engine.positions.count) + " 人")
                }
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
            if history.isEmpty { ContentUnavailableView("还没有记录", systemImage: "square.3.layers.3d", description: Text("开启空间描述后，可在这里回顾本机保存的感知结果。")) }
            ForEach(history) { entry in VStack(alignment: .leading, spacing: 8) {
                Text(entry.time.formatted() + " · " + entry.scene).font(.subheadline)
                Text(entry.message)
            } }.onDelete { offsets in var list = history; list.remove(atOffsets: offsets); save(list) }
        }.navigationTitle("感知记录").toolbar { if !history.isEmpty { EditButton() } }
    }
    var settings: some View {
        Form {
            HStack(spacing: 16) {
                Image(systemName: "viewfinder").font(.title).foregroundStyle(.white).frame(width: 56,height: 56).background(navy,in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    Image("Wordmark").resizable().scaledToFit().frame(width: 88).accessibilityLabel("TOVA")
                    Text("空间感知与语音偏好").font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 8)
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
                context.stroke(path, with: .color(Color(red: 0.60, green: 0.76, blue: 0.96).opacity(0.62)), lineWidth: 1)
            }
            for i in -5...5 {
                let n = CGFloat(i)
                line(CGPoint(x:w*(0.5+n*0.028),y:h*0.25),CGPoint(x:w*(0.5+n*0.094),y:h*0.88))
            }
            for t in [0.0,0.1,0.23,0.41,0.66,1.0] {
                let spread = w*(0.14+0.33*t), y = h*(0.25+0.63*t)
                line(CGPoint(x:w/2-spread,y:y),CGPoint(x:w/2+spread,y:y))
            }
        }
    }
}

private struct SummaryTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
