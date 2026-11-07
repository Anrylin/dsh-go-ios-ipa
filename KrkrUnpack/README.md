# KrkrUnpack

专治「`.mp4` 其实是压缩包、里面还套着 RAR」的 iOS 解包工具。
为 KiriKiri（`.xp3`）游戏准备，也能跑 Ren'Py 包。

## 它解决什么问题

Galplay / 解压专家这类 App 只解第一层，第二层是 RAR 就歇菜。这个 App 的做法：

1. **看文件头，不看后缀** —— `.mp4`、`.bin`、`.jpg` 都无所谓，`XP3` / `PK` / `Rar!` / `7z` 直接识别
2. **递归剥壳** —— zip → 里面的 rar → 里面的 7z → …… 最多 5 层，一路解到底
3. **只留游戏文件** —— 丢掉 `exe` / `dll` / `setup` / 说明文档，只保留 `.xp3` `.tjs` `.rpa`
4. **重新打包** —— 输出一个干净的 `krkr_xxx.zip`，VNPlayer 直接导入
5. **可选密码** —— 加密压缩包在界面上填密码

支持格式（libarchive 一套搞定）：ZIP / RAR4 / RAR5 / 7z / TAR / tar.gz / xz / bz2 / zstd。

## 编译（需要一台 Mac）

我没有 macOS 环境，这个工程是**源码交付**，你要自己编译。两种方式选一个。

### 方式 A：XcodeGen（推荐）

```bash
brew install xcodegen
cd KrkrUnpack
xcodegen generate
open KrkrUnpack.xcodeproj
```

### 方式 B：不装 XcodeGen，手动建

```
1. Xcode → New Project → iOS → App → 名字填 KrkrUnpack，Interface 选 SwiftUI，Language Swift
2. 删掉自动生成的 ContentView.swift 和 App 文件
3. 把本目录 Sources/ 下的 5 个 .swift 拖进工程（勾 Copy items if needed）
4. File → Add Package Dependencies… 填：
   https://github.com/Lakr233/libarchive.xcframework.git
   → 选 Add Package，product 选 ArchiveKit
5. Build Settings → Infos：把 GENERATE_INFOPLIST_FILE 关掉，加上
   UIFileSharingEnabled = YES
   LSSupportsOpeningDocumentsInPlace = YES
6. 选你的开发者 Team，插上手机，Run
```

依赖包说明：[Lakr233/libarchive.xcframework](https://github.com/Lakr233/libarchive.xcframework) —— 把 libarchive 预编译成静态 xcframework，一个包覆盖全部 Apple 平台，带 liblzma/zstd/lz4。

## 装到手机（免费 Apple ID 也能装）

```
1. Xcode 里 Signing & Capabilities → Team 选你的 Apple ID（Personal Team）
2. Bundle Identifier 改成唯一值，例如 com.你的名字.krkr
3. 手机 USB 连上 → 选设备 → Run
4. 手机：设置 → 通用 → VPN 与设备管理 → 信任你的证书
```

或者编译出 ipa 后用 Sideloadly 装：

```bash
xcodebuild -project KrkrUnpack.xcodeproj -scheme KrkrUnpack \
  -sdk iphoneos -configuration Release \
  -archivePath build/KrkrUnpack.xcarchive archive
mkdir -p build/Payload
cp -R build/KrkrUnpack.xcarchive/Products/Applications/KrkrUnpack.app build/Payload/
cd build && zip -qr KrkrUnpack.ipa Payload
```

**代价**：免费个人团队签名 **7 天过期**，到期重装一次。

## 用法

```
1. 把网盘下的 .mp4 直接传到手机（Files / 隔空投送 / iCloud 都行）
2. 打开 KrkrUnpack → 选择文件 → 选那个 .mp4
3. 有密码就填密码，没有留空
4. 等日志跑完（会显示：识别结果 → 第 1 层 → 第 2 层 → 保留 N 个文件）
5. 点「导出 krkr_xxx.zip」
6. 打开 VNPlayer → 导入这个 zip → 启动
```

日志里可以直接看到这个包的真相，例如：

```
识别结果：ZIP（原文件名 bingruomei.mp4）
第 1 层：bingruomei.zip [ZIP] 正在解压…
第 1 层完成
第 2 层：doinaka.rar [RAR (v5)] 正在解压…
第 2 层完成
保留 7 个游戏文件，丢弃 34 个无关文件（exe/dll/文档）
打包完成：krkr_1730000000.zip（7 个文件）
```

## 已知限制

| 限制 | 说明 |
|---|---|
| **多卷 RAR 不支持** | libarchive 读不了 `part1.rar` / `.r00` 这类分卷，App 会直接提示「分卷压缩包」，只能在电脑用 7-Zip 解 |
| 加密 ZIP 需要正确密码 | RAR5 加密由 libarchive 原生支持，ZIP 的 AES-256 也支持 |
| 超大包慢 | 手机解 2 GB+ 会吃内存，建议先看日志能不能跑，不行还是用电脑 |
| XP3 不解 | `.xp3` 被识别为「游戏本体」，不会被拆，原样保留 |
| 只认扩展名白名单 | 过滤阶段保留 `xp3/tjs/rpa/rpy/rpyc/pak`；如果某游戏用别的扩展，看日志「丢弃 N 个」再改 `Pipeline.swift` 里的 `gameExtensions` |

## 文件结构

```
KrkrUnpack/
  project.yml                    XcodeGen 工程描述
  Sources/
    FormatDetector.swift         16 字节魔数识别 + 分卷判定
    ArchiveExtractor.swift       libarchive 读封装 + 递归剥壳 + 铺平
    ZipWriter.swift              libarchive 写 zip
    Pipeline.swift               总流程：拷入→识别→剥壳→过滤→打包
    ContentView.swift            SwiftUI 界面 + App 入口
```

## 验证清单

```
□ 选一个改名的 .mp4，日志第一行显示的「识别结果」是否等于真实格式
□ 双层包能否一次跑完（日志里出现「第 2 层」）
□ 输出 zip 解压后是否只有一个层级的文件，没有多套目录嵌套
□ VNPlayer 导入后能启动，不再是 doinakapatch.xp3 那种 missing
```
