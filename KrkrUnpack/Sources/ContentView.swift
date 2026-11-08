import SwiftUI
import UniformTypeIdentifiers

@main
struct KrkrUnpackApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@MainActor
final class UnpackModel: ObservableObject {
    @Published var logs: [String] = []
    @Published var isRunning = false
    @Published var password: String = ""
    /// 只剥第一层：剩下的压缩包原样交出来，适合「外层能解、内层交给解压专家」。
    @Published var onlyFirstLayer: Bool = true
    @Published var outputZip: URL?
    @Published var lastError: String?

    var workRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unpack", isDirectory: true)
    }

    func log(_ line: String) {
        logs.append(line)
    }

    func start(input: URL) {
        guard !isRunning else { return }
        isRunning = true
        outputZip = nil
        lastError = nil
        logs.removeAll()

        let pw = password
        let only = onlyFirstLayer
        let root = workRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        Task {
            do {
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try Pipeline.run(input: input, password: pw, workRoot: root,
                                     onlyFirstLayer: only) { line in
                        Task { @MainActor in
                            self.logs.append(line)
                        }
                    }
                }.value

                self.logs.append("完成：\(outcome.keptFiles.count) 个文件 → \(outcome.zipURL.lastPathComponent)")
                self.outputZip = outcome.zipURL
            } catch {
                self.lastError = error.localizedDescription
                self.logs.append("失败：\(error.localizedDescription)")
            }
            self.isRunning = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = UnpackModel()
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text("选一个压缩包（.mp4/.zip/.rar/.7z 都行）")
                            .font(.headline)
                        Text("按文件头识别真实格式，自动层层解开，只留 .xp3/.tjs，最后打包成 VNPlayer 能导入的 zip。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showPicker = true
                    } label: {
                        Label("选择文件", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)

                    HStack {
                        TextField("解压密码（没有就留空）", text: $model.password)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Toggle(isOn: $model.onlyFirstLayer) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("只解第一层")
                            Text("内层压缩包（如 .rar）原样保留，交给解压专家继续")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.isRunning)

                    if model.isRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("处理中…").foregroundStyle(.secondary)
                        }
                    }

                    if let err = model.lastError {
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let zip = model.outputZip {
                        Text("已保存到：文件 App › 我的 iPhone › KrkrUnpack › Unpack")
                            .font(.caption).foregroundStyle(.secondary)
                        ShareLink(item: zip) {
                            Label("导出 \(zip.lastPathComponent)", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !model.logs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("日志").font(.headline)
                            ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("KrkrUnpack")
            .onOpenURL { url in model.start(input: url) }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { url in
                    showPicker = false
                    model.start(input: url)
                }
            }
        }
    }
}
