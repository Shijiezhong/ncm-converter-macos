import AppKit

final class Entry {
    let url: URL
    var state = "待转换"
    var detail = ""
    init(_ url: URL) { self.url = url }
}

final class DropArea: NSView {
    weak var owner: ConverterApp?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return owner?.busy == false ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let files = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        owner?.addFiles(files)
        return true
    }
}

final class ConverterApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow!
    var entries: [Entry] = []
    var busy = false
    var converterJar: URL?
    var engineError = ""
    var stopRequested = false
    var output = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/NCM转换结果")
    let table = NSTableView()
    let message = NSTextField(labelWithString: "添加文件，或把文件、文件夹拖进窗口。")
    let location = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    var addButton: NSButton!, clearButton: NSButton!, chooseButton: NSButton!, startButton: NSButton!, stopButton: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do {
            guard let bundled = Bundle.main.url(forResource: "NCM转换工具", withExtension: "jar") else { throw NSError(domain: "NCM", code: 1, userInfo: [NSLocalizedDescriptionKey: "应用内缺少转换组件"]) }
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("NCMEngine-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let engine = cache.appendingPathComponent("converter.jar")
            try FileManager.default.copyItem(at: bundled, to: engine)
            converterJar = engine
        } catch { engineError = "转换组件无法加载：" + error.localizedDescription }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "NCM 转换器 2.0"
        window.minSize = NSSize(width: 800, height: 480)
        window.delegate = self
        let root = DropArea(frame: window.contentView!.bounds)
        root.owner = self
        root.autoresizingMask = [.width, .height]
        window.contentView = root
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)])
        let title = NSTextField(labelWithString: "拖入 NCM 音乐，批量转换")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "原文件保留 · 自动检查完整性 · 还原原音频 MP3 / FLAC")
        subtitle.textColor = .secondaryLabelColor; stack.addArrangedSubview(subtitle)
        addButton = button("添加文件或文件夹", #selector(add))
        clearButton = button("清空列表", #selector(clear))
        stack.addArrangedSubview(horizontal([addButton, clearButton]))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        table.rowHeight = 38; table.usesAlternatingRowBackgroundColors = true
        for (id, title, width) in [("name", "文件", 280.0), ("state", "状态", 90.0), ("detail", "结果 / 原因", 500.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); col.title = title; col.width = width; table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = self; table.dataSource = self; scroll.documentView = table
        table.registerForDraggedTypes([.fileURL])
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        location.lineBreakMode = .byTruncatingMiddle
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chooseButton = button("更改保存位置", #selector(chooseOutput))
        let out = horizontal([location, chooseButton]); out.distribution = .fill
        stack.addArrangedSubview(out); out.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1; progress.style = .bar
        stack.addArrangedSubview(progress); progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        message.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(message); message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        startButton = button("开始转换", #selector(start)); startButton.bezelColor = .controlAccentColor; startButton.keyEquivalent = "\r"
        stopButton = button("停止后续转换", #selector(stop))
        stack.addArrangedSubview(horizontal([button("打开结果文件夹", #selector(openOutput)), stopButton, startButton]))
        refresh(); if !engineError.isEmpty { message.stringValue = engineError }; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func horizontal(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = 10; return s
    }
    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b
    }
    func refresh() {
        location.stringValue = "保存到：" + output.path; location.toolTip = output.path
        addButton.isEnabled = !busy; clearButton.isEnabled = !busy; chooseButton.isEnabled = !busy
        startButton.isEnabled = !busy && !entries.isEmpty; stopButton.isEnabled = busy && !stopRequested
    }
    @objc func add() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "添加"; panel.message = "选择 NCM 文件或文件夹，支持多选。"
        panel.beginSheetModal(for: window) { response in if response == .OK { self.addFiles(panel.urls) } }
    }
    func addFiles(_ urls: [URL]) {
        guard !busy else { return }
        busy = true; refresh(); message.stringValue = "正在查找 NCM 文件…"
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [URL] = []
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let file as URL in enumerator where file.pathExtension.lowercased() == "ncm" {
                            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { found.append(file) }
                        }
                    }
                } else if url.pathExtension.lowercased() == "ncm" { found.append(url) }
            }
            let result = found
            DispatchQueue.main.async {
                var known = Set(self.entries.map { $0.url.resolvingSymlinksInPath().path }); var added = 0
                for url in result {
                    let canonical = url.resolvingSymlinksInPath()
                    if known.insert(canonical.path).inserted { self.entries.append(Entry(canonical)); added += 1 }
                }
                self.busy = false; self.refresh(); self.table.reloadData()
                self.message.stringValue = "已添加 \(added) 个文件，共 \(self.entries.count) 个；重复选择的文件自动忽略。"
            }
        }
    }
    @objc func clear() { entries.removeAll(); table.reloadData(); progress.doubleValue = 0; message.stringValue = "列表已清空，原文件和转换结果保留。"; refresh() }
    @objc func chooseOutput() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "保存到这里"
        panel.beginSheetModal(for: window) { if $0 == .OK, let url = panel.url { self.output = url; self.refresh() } }
    }
    @objc func stop() { stopRequested = true; refresh(); message.stringValue = "当前文件完成后停止，已成功的结果保留。" }
    @objc func openOutput() {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true); NSWorkspace.shared.open(output) }
        catch { message.stringValue = "无法打开结果文件夹：" + error.localizedDescription }
    }
    @objc func start() {
        guard !busy else { return }
        busy = true; stopRequested = false; refresh()
        let batch = entries, folder = output
        progress.maxValue = Double(batch.count); progress.doubleValue = 0
        guard let jar = converterJar, FileManager.default.fileExists(atPath: jar.path) else { busy = false; refresh(); message.stringValue = "应用文件不完整，请重新复制整个应用。"; return }
        DispatchQueue.global(qos: .userInitiated).async {
            var success = 0, failed = 0, report = "NCM转换器 2.0\n\(Date())\n保存到：\(folder.path)\n\n"
            for (index, item) in batch.enumerated() {
                var stopped = false
                DispatchQueue.main.sync { stopped = self.stopRequested; if !stopped { item.state = "转换中"; item.detail = "正在检查音频…"; self.table.reloadData(); self.message.stringValue = "\(index + 1) / \(batch.count)：\(item.url.lastPathComponent)" } }
                if stopped { break }
                let p = Process(), pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/java")
                p.arguments = ["-Dfile.encoding=UTF-8", "-Xmx1536m", "-jar", jar.path, "--output", folder.path, item.url.path]
                p.standardOutput = pipe; p.standardError = pipe
                var text = "", ok = false
                do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); text = String(data: data, encoding: .utf8) ?? "无法读取工具返回的信息"; ok = p.terminationStatus == 0 }
                catch { text = "无法启动 Java，请确认 JDK 8 已安装。\n" + error.localizedDescription }
                if ok { success += 1 } else { failed += 1 }
                let lines = text.components(separatedBy: .newlines)
                var detail = lines.first(where: { $0.hasPrefix(ok ? "成功：" : "失败：") }) ?? text
                if !ok && text.contains("FLAC音频帧校验失败") { detail = "音频数据校验未通过，请重新下载原 NCM 文件后重试。" }
                report += item.url.path + "\n" + text + "\n"
                let finalDetail = detail, finalOK = ok
                DispatchQueue.main.sync { item.state = finalOK ? "成功" : "需重新处理"; item.detail = finalDetail; self.table.reloadData(); self.progress.doubleValue = Double(index + 1) }
            }
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"; let log = folder.appendingPathComponent("转换记录-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4)).txt"); try report.write(to: log, atomically: true, encoding: .utf8) }
            catch { report += "记录保存失败：" + error.localizedDescription }
            let okCount = success, badCount = failed
            DispatchQueue.main.async { self.busy = false; self.refresh(); self.message.stringValue = "\(self.stopRequested ? "已停止" : "处理完成")：成功 \(okCount) 个，需重新处理 \(badCount) 个。点击“打开结果文件夹”查看。" }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = entries[row], id = tableColumn?.identifier.rawValue ?? "name"
        let value = id == "name" ? item.url.lastPathComponent : id == "state" ? item.state : item.detail
        let label = NSTextField(labelWithString: value); label.lineBreakMode = .byTruncatingMiddle; label.font = .systemFont(ofSize: 13); label.toolTip = id == "name" ? item.url.path : value
        if id == "state" { label.textColor = item.state == "成功" ? .systemGreen : item.state == "需重新处理" ? .systemOrange : .labelColor }
        return label
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation { tableView.setDropRow(-1, dropOperation: .on); return busy ? [] : .copy }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard !busy, let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        addFiles(urls); return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if busy { message.stringValue = "请先停止后续转换，等待当前文件完成。" }; return !busy }
    func applicationWillTerminate(_ notification: Notification) { if let jar = converterJar { try? FileManager.default.removeItem(at: jar.deletingLastPathComponent()) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { addFiles(filenames.map { URL(fileURLWithPath: $0) }); sender.reply(toOpenOrPrint: .success) }
}

let app = NSApplication.shared
let delegate = ConverterApp()
app.delegate = delegate
app.run()
