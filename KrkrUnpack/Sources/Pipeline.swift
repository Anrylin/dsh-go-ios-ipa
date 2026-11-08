import Foundation

/// 完整流程：拷入 → 识别 → 递归剥壳 → 过滤出游戏文件 → 重新打包成 VNPlayer 能吃的 zip
enum Pipeline {

    struct Outcome {
        let flatFolder: URL
        let gameFolder: URL
        let zipURL: URL
        let detected: DetectedFormat
        let keptFiles: [String]
        let droppedCount: Int
    }

    private static let gameExtensions: Set<String> = ["xp3", "tjs", "rpa", "rpy", "rpyc", "pak"]

    static func run(input rawInput: URL,
                    password: String?,
                    workRoot: URL,
                    onlyFirstLayer: Bool = false,
                    onLog: @escaping (String) -> Void) throws -> Outcome {

        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let jobDir = workRoot.appendingPathComponent("job_\(stamp)")
        try fm.createDirectory(at: jobDir, withIntermediateDirectories: true)

        // 1. 拷入工作区（同时解除 iOS 的安全作用域限制）
        onLog("拷入文件…")
        let inputName = rawInput.lastPathComponent.isEmpty ? "input.bin" : rawInput.lastPathComponent
        let localInput = jobDir.appendingPathComponent(inputName)
        let scoped = rawInput.startAccessingSecurityScopedResource()
        defer { if scoped { rawInput.stopAccessingSecurityScopedResource() } }
        try fm.copyItem(at: rawInput, to: localInput)

        // 2. 识别真实格式
        let fmt = FormatDetector.detect(localInput)
        onLog("识别结果：\(fmt.displayName)（原文件名 \(inputName)）")
        onLog(fmt.advice)

        // 视频头但后面拼了压缩包：这是最常见的伪装（.mp4 = 视频 + zip）。
        var workingInput = localInput
        if !fmt.isArchive, fmt == .mp4 {
            if let found = EmbeddedArchive.find(in: localInput, onLog: onLog) {
                workingInput = (try? EmbeddedArchive.carve(url: localInput, from: found.offset)) ?? localInput
            } else {
                throw UnpackError.openFailed("\(fmt.displayName)，而且后面没有拼接任何压缩包。这是真的视频，换资源。")
            }
        }
        guard fmt.isArchive || workingInput != localInput else {
            throw UnpackError.openFailed("\(fmt.displayName) 不能解压。\(fmt.advice)")
        }

        // 3. 递归剥壳
        let unpackRoot = jobDir.appendingPathComponent("unpack")
        try fm.createDirectory(at: unpackRoot, withIntermediateDirectories: true)
        let flat = try RecursiveUnpacker.unpack(
            workingInput,
            into: unpackRoot,
            password: password,
            maxDepth: onlyFirstLayer ? 1 : 5,
            onLog: onLog
        )

        // 4. 过滤：KiriKiri 只留 .xp3/.tjs；Ren'Py 结构则整棵树保留
        onLog("整理游戏文件…")
        let gameDir = jobDir.appendingPathComponent("Game")
        try? fm.removeItem(at: gameDir)
        try fm.createDirectory(at: gameDir, withIntermediateDirectories: true)

        let allFiles = (try? fm.contentsOfDirectory(at: flat, includingPropertiesForKeys: nil)) ?? []
        let looksLikeRenPy = fm.fileExists(atPath: flat.appendingPathComponent("game").path)
            && fm.fileExists(atPath: flat.appendingPathComponent("renpy").path)

        // 先把第一层解出来的东西列出来：分卷包缺卷时，看这一行就知道。
        let topNames = allFiles.map(\.lastPathComponent).sorted()
        if !topNames.isEmpty {
            onLog("解出 \(topNames.count) 项：\(topNames.prefix(12).joined(separator: " / "))\(topNames.count > 12 ? " …" : "")")
        }

        var kept: [String] = []
        var dropped = 0

        if onlyFirstLayer {
            // 只剥第一层：把解出来的东西**原样**打包，剩下的压缩包交给别的工具。
            for item in allFiles {
                try? fm.copyItem(at: item, to: gameDir.appendingPathComponent(item.lastPathComponent))
                kept.append(item.lastPathComponent)
            }
        } else if looksLikeRenPy {
            for item in allFiles {
                try? fm.copyItem(at: item, to: gameDir.appendingPathComponent(item.lastPathComponent))
                kept.append(item.lastPathComponent)
            }
            onLog("检测到 Ren'Py 目录结构，整棵保留")
        } else {
            for item in allFiles {
                let ext = item.pathExtension.lowercased()
                if gameExtensions.contains(ext) {
                    try? fm.copyItem(at: item, to: gameDir.appendingPathComponent(item.lastPathComponent))
                    kept.append(item.lastPathComponent)
                } else {
                    dropped += 1
                }
            }
        }

        guard !kept.isEmpty else {
            throw UnpackError.emptyArchive("没有找到 .xp3/.tjs 文件，可能不是 KiriKiri 游戏包")
        }
        onLog("保留 \(kept.count) 个游戏文件，丢弃 \(dropped) 个无关文件（exe/dll/文档）")

        // 5. 打包
        let zipURL = jobDir.appendingPathComponent("krkr_\(stamp).zip")
        try ZipWriter.zip(folder: gameDir, to: zipURL, onLog: onLog)

        return Outcome(flatFolder: flat, gameFolder: gameDir, zipURL: zipURL,
                       detected: fmt, keptFiles: kept, droppedCount: dropped)
    }
}
