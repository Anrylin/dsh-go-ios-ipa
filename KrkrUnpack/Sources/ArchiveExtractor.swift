import Foundation
import ArchiveKit

enum UnpackError: LocalizedError {
    case openFailed(String)
    case readFailed(String)
    case splitVolume(String)
    case emptyArchive(String)
    case depthExceeded(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let s): return "打开压缩包失败：\(s)"
        case .readFailed(let s): return "读取压缩包失败：\(s)"
        case .splitVolume(let s): return "分卷压缩包：\(s)"
        case .emptyArchive(let s): return "压缩包里没有文件：\(s)"
        case .depthExceeded(let s): return "嵌套层数过多：\(s)"
        }
    }
}

/// libarchive 的 Swift 封装：只用一套 C API，就能读 zip / rar4 / rar5 / 7z / tar / gz / xz / bz2 / zstd。
final class ArchiveExtractor {

    private static func errorString(_ a: OpaquePointer?) -> String {
        guard let a, let c = archive_error_string(a) else { return "unknown" }
        return String(cString: c)
    }

    /// 把 archive 解压到 destination（自动创建目录，防目录穿越）
    static func extract(archiveURL: URL, to destination: URL, password: String?) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let a = archive_read_new() else {
            throw UnpackError.openFailed("archive_read_new")
        }
        defer { archive_read_free(a) }

        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)

        if let pw = password, !pw.isEmpty {
            pw.withCString { _ = archive_read_add_passphrase(a, $0) }
        }

        let openResult: Int32 = archiveURL.path.withCString { cpath in
            archive_read_open_filename(a, cpath, 128 * 1024)
        }
        guard openResult == ARCHIVE_OK else {
            throw UnpackError.openFailed(errorString(a))
        }

        let rootPath = destination.standardizedFileURL.path
        let fm = FileManager.default
        var entry: OpaquePointer?
        var count = 0

        while true {
            let rc = archive_read_next_header(a, &entry)
            if rc == ARCHIVE_EOF { break }
            if rc != ARCHIVE_OK && rc != ARCHIVE_WARN {
                throw UnpackError.readFailed(errorString(a))
            }
            guard let entry else { continue }

            guard let cName = archive_entry_pathname(entry) else { continue }
            var name = String(cString: cName)

            // 去掉绝对路径与 ..，防目录穿越
            while name.hasPrefix("/") { name.removeFirst() }
            name = name.replacingOccurrences(of: "../", with: "")
            if name.isEmpty { continue }

            let isDir = (Int(archive_entry_filetype(entry)) & 0o170000) == 0o040000 || name.hasSuffix("/")
            let target = destination.appendingPathComponent(name).standardizedFileURL
            guard target.path.hasPrefix(rootPath) else { continue }

            if isDir {
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                archive_read_data_skip(a)
                continue
            }

            try? fm.createDirectory(at: target.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)

            fm.createFile(atPath: target.path, contents: nil)
            guard let out = try? FileHandle(forWritingTo: target) else {
                archive_read_data_skip(a)
                continue
            }
            defer { try? out.close() }

            var buffer = [UInt8](repeating: 0, count: 512 * 1024)
            while true {
                let n = buffer.withUnsafeMutableBytes { ptr -> Int in
                    archive_read_data(a, ptr.baseAddress, ptr.count)
                }
                if n < 0 { throw UnpackError.readFailed(errorString(a)) }
                if n == 0 { break }
                try out.write(contentsOf: Data(buffer[0..<n]))
            }
            count += 1
        }

        if count == 0 {
            throw UnpackError.emptyArchive(archiveURL.lastPathComponent)
        }
    }
}

/// 递归剥壳：zip 里套 rar、rar 里套 7z、7z 里套 zip……一直解到没有压缩包为止。
enum RecursiveUnpacker {

    /// - Returns: 最终铺平后的目录
    @discardableResult
    static func unpack(_ file: URL,
                       into root: URL,
                       password: String?,
                       maxDepth: Int = 5,
                       onLog: @escaping (String) -> Void) throws -> URL {

        let fm = FileManager.default
        var currentRoot = root

        if FormatDetector.isSplitVolume(file) {
            throw UnpackError.splitVolume(file.lastPathComponent)
        }

        let fmt = FormatDetector.detect(file)
        guard fmt.isArchive else {
            throw UnpackError.openFailed("不是可解压格式，识别为：\(fmt.displayName)")
        }

        var level = 0
        var pending: [URL] = [file]

        while !pending.isEmpty {
            guard level < maxDepth else {
                throw UnpackError.depthExceeded("超过 \(maxDepth) 层")
            }
            level += 1

            var nextRound: [URL] = []
            for archiveURL in pending {
                let fmt = FormatDetector.detect(archiveURL)
                guard fmt.isArchive else { continue }

                let name = archiveURL.deletingPathExtension().lastPathComponent
                let outDir = currentRoot.appendingPathComponent("L\(level)_\(sanitize(name))")
                onLog("第 \(level) 层：\(archiveURL.lastPathComponent) [\(fmt.displayName)] 正在解压…")

                try ArchiveExtractor.extract(archiveURL: archiveURL, to: outDir, password: password)

                // 解压成功后删除这一层压缩包，避免重复占空间
                try? fm.removeItem(at: archiveURL)

                // 找出这一层里还藏着哪些压缩包
                nextRound.append(contentsOf: findArchives(in: outDir))
                currentRoot = outDir
                onLog("第 \(level) 层完成 → \(outDir.lastPathComponent)")
            }
            pending = nextRound
        }

        // 铺平：把所有非压缩包文件集中到 All/ 下
        let flat = root.appendingPathComponent("All")
        try? fm.removeItem(at: flat)
        try fm.createDirectory(at: flat, withIntermediateDirectories: true)
        try flatten(from: root, to: flat, skipping: flat)
        return flat
    }

    /// 在目录里找可解压文件；如果目录只有一个子目录，往里再找一层
    static func findArchives(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }

        var archives: [URL] = []
        var others: [URL] = []
        for item in items {
            if FormatDetector.detect(item).isArchive {
                archives.append(item)
            } else {
                others.append(item)
            }
        }
        if archives.isEmpty, others.count == 1,
           let isDir = try? others[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true {
            return findArchives(in: others[0])
        }
        return archives
    }

    private static func flatten(from dir: URL, to dest: URL, skipping: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                               options: [.skipsHiddenFiles])
        for item in items {
            if item.standardizedFileURL == skipping.standardizedFileURL { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                try flatten(from: item, to: dest, skipping: skipping)
            } else {
                var target = dest.appendingPathComponent(item.lastPathComponent)
                var i = 2
                while fm.fileExists(atPath: target.path) {
                    let base = item.deletingPathExtension().lastPathComponent
                    let ext = item.pathExtension
                    let newName = ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)"
                    target = dest.appendingPathComponent(newName)
                    i += 1
                }
                try? fm.copyItem(at: item, to: target)
            }
        }
    }

    static func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return s.components(separatedBy: bad).joined(separator: "_")
    }
}
