# NCM Converter for macOS

一个轻量的 Mac 原生 NCM 音频转换工具。拖入文件或文件夹，批量还原其中的 **MP3 / FLAC**，保留原文件。

## 下载与使用

1. 在 [Releases](https://github.com/Shijiezhong/ncm-converter-macos/releases/latest) 下载应用 ZIP 并解压。
2. 将 `NCM转换器.app` 放到「应用程序」或桌面，双击打开。
3. 拖入 `.ncm` 文件或文件夹，点击「开始转换」。
4. 完成后点击「打开结果文件夹」。默认保存到桌面的 `NCM转换结果`，也可更改。

需要 **macOS 14 或更新版本**及已安装的 **Java 8 或更新版本**。发行包的原生界面支持 Apple Silicon 和 Intel；Java 运行环境需另外安装，可从 [Amazon Corretto](https://aws.amazon.com/corretto/) 或 [Eclipse Temurin](https://adoptium.net/) 的官方网站获取。

发行包采用本地 ad-hoc 签名，**没有 Apple Developer ID 签名或公证**。macOS 可能阻止首次打开。也可以使用下文的命令从源码构建；本项目不要求关闭系统安全保护。

## 功能

- 原生 macOS 窗口，支持拖放、多选和文件夹递归查找。
- 后台逐首转换，显示进度与结果，可停止后续任务。
- 原文件不改动；相同音频复用已有输出，同名不同内容自动编号。
- 验证后写入，写入失败时清理临时文件。
- 处理封面预留区，以及部分文件中音频前出现的重复封面或额外数据。
- 每批生成本地转换记录；不上传音乐、不收集遥测。
- 应用启动时缓存转换组件，移动正在运行的应用不会使组件路径立即失效。

## 输出格式和限制

本工具是**还原原音频**，不是重新编码器：原内容为 MP3 就输出 MP3，为 FLAC 就输出 FLAC。不会将所有文件强制压缩为 MP3，也不会提高音质。

MP3 会检查连续音频帧结构；FLAC 会检查元数据、帧头校验、音频帧 CRC 和总采样数。此类检查不能替代完整 PCM 解码或试听，也无法修复原本缺失的音乐数据。未知格式、损坏文件可能无法转换，请提交不含歌曲的错误记录帮助排查。

当前单文件上限为 512 MiB；兼容性搜索范围为正常音频起点后 16 MiB。保留音频流已有的标签，暂不另外写入 NCM 容器中的歌曲标签与封面。

## 从源码构建

需要 JDK 8+、Xcode Command Line Tools 和 macOS。无需 Maven 或第三方 Java 依赖。

```bash
git clone https://github.com/Shijiezhong/ncm-converter-macos.git
cd ncm-converter-macos
bash test.sh
bash build.sh
```

默认构建本机架构，生成 `dist/NCM转换器.app`、应用 ZIP 和命令行 JAR。

构建 Apple Silicon + Intel 通用版本：

```bash
ARCH=universal bash build.sh
```

## 命令行

Java 核心可在有 Java 8+ 的系统上使用；原生窗口仅适用于 macOS。

```bash
java -Xmx1536m -jar dist/ncm-converter.jar --output ./converted "/path/to/song.ncm" "/path/to/folder"
```

不传 `--output` 时，各原文件旁会生成 `转换结果` 文件夹。批处理中单个文件出错后仍会继续，存在失败时返回非零退出码。无参数启动 JAR 会打开备用 Swing 界面。

## 测试与反馈

自动化测试使用程序生成的合成音频和 NCM 包装，不提交任何歌曲。覆盖 MP3/FLAC、封面预留区、额外前缀、校验失败、截断文件、重复输出和同名冲突。

反馈问题时，请提供版本、macOS / Java 版本、错误文字和可复现步骤。**请勿把歌曲、账号信息或包含个人路径的完整日志公开上传**；先删除日志中的个人信息。

## 致谢与许可证

本项目在 [charlotte-xiao/NCM2MP3](https://github.com/charlotte-xiao/NCM2MP3) 的公开格式说明和实践启发下实现，增加原生界面与文件布局兼容处理；不是该项目的官方发行版，也不包含其 JAR 或第三方 Java 依赖。

本仓库代码采用 [MIT License](LICENSE)。仅处理你有权使用的本地文件；许可证不授予任何音乐作品的权利。

---

**English:** A native macOS batch converter that restores MP3/FLAC audio from local NCM files. Requires Java 8+. Originals are preserved; matching outputs are reused. Download the universal macOS app from Releases, or build with `ARCH=universal bash build.sh`. Audio structure checks do not guarantee support for every NCM variant or repair missing data. No music files are included in this repository.
