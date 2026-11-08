// 「视频 + 压缩包」拼接文件：真实资源追加在 mp4 后面。
// 这里扫描文件里第一个**能被 libarchive 打开**的压缩包起点，再把它切出来。

import Foundation
import ArchiveKit

enum EmbeddedArchive {
    /// 找第一个可用的压缩包偏移；没有就返回 nil。
    /// 只扫到前 512 MB：再往后基本是视频数据，扫了也白扫。
    static func find(in url: URL, limit: UInt64 = 512 * 1024 * 1024, onLog: (String) -> Void) -> (offset: UInt64, label: String)? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        let end = min(limit, size)
        let sigs: [(Data, String)] = [
            (Data([0x50, 0x4B, 0x03, 0x04]), "ZIP"),
            (Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]), "RAR"),
            (Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]), "7-Zip"),
        ]

        var offset: UInt64 = 0
        let chunk = 4 * 1024 * 1024
        var carry = Data()
        while offset < end {
            guard let data = try? fh.read(upToCount: chunk), !data.isEmpty else { break }
            var buffer = carry + data
            let base = offset == 0 ? 0 : offset - UInt64(carry.count)
            for (sig, label) in sigs {
                var search = buffer.startIndex
                while let r = buffer.range(of: sig, in: search..<buffer.endIndex) {
                    let at = base + UInt64(buffer.distance(from: buffer.startIndex, to: r.lowerBound))
                    if at > 0, let carved = try? carve(url: url, from: at), canOpen(carved) {
                        onLog("在第 \(at) 字节处找到内嵌 \(label)，从这里开始解")
                        return (at, label)
                    }
                    search = buffer.index(after: r.lowerBound)
                }
            }
            let keep = 8
            carry = buffer.suffix(keep)
            offset += UInt64(data.count)
        }
        return nil
    }

    /// 从 offset 起切一份临时文件（大文件按块拷，别一次性读进内存）。
    static func carve(url: URL, from offset: UInt64) throws -> URL {
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("carved_\(offset).bin")
        if FileManager.default.fileExists(atPath: dst.path) { return dst }
        guard let src = try? FileHandle(forReadingFrom: url) else {
            throw UnpackError.readFailed("无法打开源文件")
        }
        defer { try? src.close() }
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        guard let out = try? FileHandle(forWritingTo: dst) else {
            throw UnpackError.readFailed("无法创建临时文件")
        }
        defer { try? out.close() }
        try src.seek(toOffset: offset)
        while let data = try? src.read(upToCount: 8 * 1024 * 1024), !data.isEmpty {
            try out.write(contentsOf: data)
        }
        return dst
    }

    /// 用 libarchive 试着打开：能列出条目就算可用。
    static func canOpen(_ url: URL) -> Bool {
        guard let a = archive_read_new() else { return false }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)
        let ok = url.path.withCString { archive_read_open_filename(a, $0, 128 * 1024) } == ARCHIVE_OK
        guard ok else { return false }
        var entry: OpaquePointer?
        let listed = archive_read_next_header(a, &entry) == ARCHIVE_OK
        return listed
    }
}
