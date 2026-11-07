import Foundation
import ArchiveKit

/// 用 libarchive 写 zip（iOS 上没有系统级 zip 命令，所以自己打包）
enum ZipWriter {

    static func zip(folder: URL, to zipURL: URL, onLog: ((String) -> Void)? = nil) throws {
        try? FileManager.default.removeItem(at: zipURL)

        guard let w = archive_write_new() else {
            throw UnpackError.openFailed("archive_write_new")
        }
        defer { archive_write_free(w) }

        archive_write_set_format_zip(w)
        _ = "zip:compression=deflate".withCString { archive_write_set_options(w, $0) }

        let rcOpen = zipURL.path.withCString { archive_write_open_filename(w, $0) }
        guard rcOpen == ARCHIVE_OK else {
            throw UnpackError.openFailed("无法创建 \(zipURL.lastPathComponent)")
        }

        let fm = FileManager.default
        var files: [URL] = []
        collectFiles(in: folder, into: &files)

        for file in files {
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  let size = attrs[.size] as? NSNumber else { continue }
            let rel = file.path.replacingOccurrences(of: folder.path + "/", with: "")

            guard let entry = archive_entry_new() else { continue }
            defer { archive_entry_free(entry) }

            rel.withCString { archive_entry_set_pathname(entry, $0) }
            archive_entry_set_filetype(entry, 0o100000)
            archive_entry_set_perm(entry, 0o644)
            archive_entry_set_size(entry, size.int64Value)

            if archive_write_header(w, entry) != ARCHIVE_OK {
                onLog?("跳过（无法写入头）：\(rel)")
                continue
            }

            guard let fh = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? fh.close() }
            while true {
                let data = try fh.read(upToCount: 512 * 1024) ?? Data()
                if data.isEmpty { break }
                _ = data.withUnsafeBytes { ptr in
                    archive_write_data(w, ptr.baseAddress, ptr.count)
                }
            }
        }

        archive_write_close(w)
        onLog?("打包完成：\(zipURL.lastPathComponent)（\(files.count) 个文件）")
    }

    private static func collectFiles(in dir: URL, into list: inout [URL]) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { return }
        for item in items {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                collectFiles(in: item, into: &list)
            } else {
                list.append(item)
            }
        }
    }
}
