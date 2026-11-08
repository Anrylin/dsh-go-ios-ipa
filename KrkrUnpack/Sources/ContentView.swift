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
        let root = workRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        Task {
            do {
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try Pipeline.run(input: input, password: pw, workRoot: root) { line in
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
            .fileImporter(isPresented: $showPicker,
                          // `.item` 是抽象类型，系统有时把普通文件灰掉；把常见的具体类型都放进来。
                          allowedContentTypes: [.data, .archive, .zip, .movie, .audio, .image, .text, .item],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        model.lastError = "没有拿到文件地址。换一种方式：在「文件」App 里长按 → 共享 → KrkrUnpack。"
                        return
                    }
                    // 有些第三方文件提供方（网盘、iCloud 未下载）会返回一个暂时读不到的地址,
                    // 先探一下再交给流程，失败时给出人能看懂的话。
                    let scoped = url.startAccessingSecurityScopedResource()
                    let readable = (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    guard readable else {
                        model.lastError = "这个文件当前读不到（可能没下载完，或来自不支持的文件提供方）。先在「文件」App 里把它拷贝到「我的 iPhone」，或长按 → 共享 → KrkrUnpack。"
                        return
                    }
                    model.start(input: url)
                case .failure(let err):
                    model.lastError = err.localizedDescription
                }
            }
        }
    }
}
