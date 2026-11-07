import Foundation

/// 按文件头（magic bytes）识别真实格式，完全忽略扩展名。
/// 这是整个 App 的第一层，专门对付「.mp4 其实是压缩包」这类伪装。
enum DetectedFormat: String {
    case zip
    case rar4
    case rar5
    case sevenZip
    case tar
    case gzip
    case bzip2
    case xz
    case zstd
    case xp3
    case mp4
    case html
    case json
    case pe
    case ole
    case unknown

    /// libarchive 能读的格式
    var isArchive: Bool {
        switch self {
        case .zip, .rar4, .rar5, .sevenZip, .tar, .gzip, .bzip2, .xz, .zstd:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .zip: return "ZIP"
        case .rar4: return "RAR (v4)"
        case .rar5: return "RAR (v5)"
        case .sevenZip: return "7-Zip"
        case .tar: return "TAR"
        case .gzip: return "GZip / tar.gz"
        case .bzip2: return "BZip2"
        case .xz: return "XZ"
        case .zstd: return "Zstd"
        case .xp3: return "XP3（KiriKiri 游戏本体）"
        case .mp4: return "真正的 MP4 视频"
        case .html: return "HTML 网页（下载失败）"
        case .json: return "JSON 报错（下载失败）"
        case .pe: return "Windows EXE"
        case .ole: return "OLE / 老式自解压包"
        case .unknown: return "未知"
        }
    }

    /// 给用户的下一步提示
    var advice: String {
        switch self {
        case .xp3:
            return "不是压缩包，是 KiriKiri 游戏数据。改名成 .xp3 后放进游戏目录直接运行，不要解压。"
        case .mp4:
            return "这是真的视频，属于引流诱饵，改成任何后缀都没用，需要换资源。"
        case .html, .json:
            return "下载到的是错误页而不是文件，说明直链过期或需要登录，回资源站重新取链接。"
        case .pe, .ole:
            return "这是 Windows 程序，需要在电脑上运行，iOS 端用不了。"
        case .unknown:
            return "无法识别，可能下载不完整或被加密包裹。"
        default:
            return "可以解压。"
        }
    }
}

enum FormatDetector {

    static func detect(_ url: URL) -> DetectedFormat {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 512), data.count >= 4 else {
            return .unknown
        }
        let bytes = [UInt8](data)
        return classify(bytes)
    }

    private static func classify(_ b: [UInt8]) -> DetectedFormat {
        func at(_ i: Int, _ v: UInt8) -> Bool { b.count > i && b[i] == v }
        func seq(_ i: Int, _ s: [UInt8]) -> Bool {
            guard b.count >= i + s.count else { return false }
            for (k, v) in s.enumerated() where b[i + k] != v { return false }
            return true
        }

        // XP3: 58 50 33 0D 0A 20 0A 1A 8B 67 01
        if b.count >= 11 && b[0] == 0x58 && b[1] == 0x50 && b[2] == 0x33
            && seq(3, [0x0D, 0x0A, 0x20, 0x0A, 0x1A, 0x8B, 0x67, 0x01]) {
            return .xp3
        }
        // ZIP: PK\x03\x04 / PK\x05\x06(空) / PK\x07\x08(分卷)
        if b[0] == 0x50 && b[1] == 0x4B,
           at(2, 0x03) || at(2, 0x05) || at(2, 0x07) {
            return .zip
        }
        // RAR5: 52 61 72 21 1A 07 01 00
        if seq(0, [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) { return .rar5 }
        // RAR4: 52 61 72 21 1A 07 00
        if seq(0, [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]) { return .rar4 }
        // 7z: 37 7A BC AF 27 1C
        if seq(0, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip }
        // gzip: 1F 8B
        if seq(0, [0x1F, 0x8B]) { return .gzip }
        // bzip2: 42 5A 68
        if seq(0, [0x42, 0x5A, 0x68]) { return .bzip2 }
        // xz: FD 37 7A 58 5A 00
        if seq(0, [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .xz }
        // zstd: 28 B5 2F FD
        if seq(0, [0x28, 0xB5, 0x2F, 0xFD]) { return .zstd }
        // tar: offset 257 处 "ustar"
        if b.count > 262, seq(257, [0x75, 0x73, 0x74, 0x61, 0x72]) { return .tar }
        // MP4 / MOV: offset 4 处 "ftyp"
        if b.count > 8, seq(4, [0x66, 0x74, 0x79, 0x70]) { return .mp4 }
        // Windows PE: MZ
        if seq(0, [0x4D, 0x5A]) { return .pe }
        // OLE: D0 CF 11 E0
        if seq(0, [0xD0, 0xCF, 0x11, 0xE0]) { return .ole }
        // HTML / JSON
        if seq(0, [0x3C, 0x21]) || seq(0, [0x3C, 0x68]) || seq(0, [0x3C, 0x48]) { return .html }
        if seq(0, [0x7B, 0x22]) { return .json }

        return .unknown
    }

    /// 分卷（libarchive 不支持多卷 RAR/ZIP，必须电脑处理）
    static func isSplitVolume(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.range(of: #"\.part\d+\.rar$"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"\.r\d{2}$"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"\.z\d{2}$"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"\.\d{3}$"#, options: .regularExpression) != nil { return true }
        if name.hasSuffix(".001") { return true }
        return false
    }
}
