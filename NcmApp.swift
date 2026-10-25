import AppKit

final class TealProgress: NSProgressIndicator {
    override var doubleValue: Double { didSet { needsDisplay = true } }
    override var maxValue: Double { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - 4) / 2, width: bounds.width, height: 4)
        NSColor.separatorColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        let value = maxValue > 0 ? max(0, min(1, doubleValue / maxValue)) : 0
        if value > 0 { NSColor.systemTeal.setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: track.minY, width: bounds.width * value, height: 4), xRadius: 2, yRadius: 2).fill() }
    }
}

final class Entry {
    let url: URL
    var state = "待转换"
    var detail = ""
    init(_ url: URL) { self.url = url }
}

final class DropArea: NSView {
    weak var owner: ConverterApp?
    var styled = false
    var hovering = false
    override func draw(_ dirtyRect: NSRect) {
        guard styled else { return }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        NSColor.systemTeal.withAlphaComponent(hovering ? 0.12 : 0.035).setFill(); shape.fill()
        NSColor.systemTeal.withAlphaComponent(hovering ? 0.85 : 0.32).setStroke()
        shape.lineWidth = 1.4; shape.setLineDash([6, 5], count: 2, phase: 0); shape.stroke()
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false; needsDisplay = true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovering = owner?.busy == false; needsDisplay = true; return hovering ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let files = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        hovering = false; needsDisplay = true; owner?.addFiles(files)
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
    let countLabel = NSTextField(labelWithString: "转换列表 · 0 首")
    let emptyState = NSStackView()
    let message = NSTextField(labelWithString: "添加文件，或把文件、文件夹拖进窗口。")
    let location = NSTextField(labelWithString: "")
    let progress = TealProgress()
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
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "退出 NCM 转换器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "NCM 转换器"
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.minSize = NSSize(width: 850, height: 760)
        window.delegate = self
        let root = DropArea(frame: window.contentView!.bounds)
        root.owner = self; root.autoresizingMask = [.width, .height]
        window.contentView = root
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)])
        let emblem = NSImageView(image: NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "音频转换")!)
        emblem.contentTintColor = .systemTeal; emblem.symbolConfiguration = .init(pointSize: 46, weight: .light)
        emblem.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let title = label("NCM 音频转换", size: 27, weight: .semibold)
        let subtitle = label("让下载的音乐，在更多播放器里播放。", size: 13, color: .secondaryLabelColor)
        let titles = NSStackView(views: [title, subtitle]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 7
        let header = horizontal([emblem, titles, spacer()])
        header.spacing = 15; stack.addArrangedSubview(header); header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let drop = DropArea(); drop.owner = self; drop.styled = true
        drop.translatesAutoresizingMaskIntoConstraints = false; stack.addArrangedSubview(drop)
        drop.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; drop.heightAnchor.constraint(equalToConstant: 140).isActive = true
        let dropIcon = NSImageView(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "拖入音乐")!)
        dropIcon.contentTintColor = .systemTeal; dropIcon.symbolConfiguration = .init(pointSize: 27, weight: .regular)
        let dropText = NSStackView(views: [label("把音乐拖到这里", size: 17, weight: .semibold), label("支持多个 NCM 文件，也可以添加整个文件夹", size: 12, color: .secondaryLabelColor)])
        dropText.orientation = .vertical; dropText.alignment = .leading; dropText.spacing = 8
        addButton = button("选择文件", #selector(add)); addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil); addButton.imagePosition = .imageLeading
        let dropContents = horizontal([dropIcon, dropText, spacer(), addButton]); dropContents.spacing = 18; dropContents.translatesAutoresizingMaskIntoConstraints = false; drop.addSubview(dropContents)
        NSLayoutConstraint.activate([dropContents.leadingAnchor.constraint(equalTo: drop.leadingAnchor, constant: 26), dropContents.trailingAnchor.constraint(equalTo: drop.trailingAnchor, constant: -26), dropContents.centerYAnchor.constraint(equalTo: drop.centerYAnchor)])
        countLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        clearButton = button("清空列表", #selector(clear)); clearButton.isBordered = false; clearButton.contentTintColor = .secondaryLabelColor
        let listHeader = horizontal([countLabel, spacer(), clearButton]); stack.addArrangedSubview(listHeader); listHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let card = NSBox(); card.boxType = .custom; card.titlePosition = .noTitle; card.cornerRadius = 14; card.borderWidth = 1
        card.borderColor = NSColor.separatorColor.withAlphaComponent(0.35); card.fillColor = .controlBackgroundColor; card.contentViewMargins = .zero
        stack.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; card.heightAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder; scroll.drawsBackground = false
        table.rowHeight = 62; table.intercellSpacing = NSSize(width: 18, height: 1); table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .controlBackgroundColor; table.gridStyleMask = []; table.gridColor = NSColor.separatorColor.withAlphaComponent(0.2)
        table.style = .fullWidth
        for (id, title, width) in [("name", "音乐文件", 350.0), ("state", "状态", 110.0), ("detail", "转换结果", 380.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); col.title = title; col.width = width
            col.minWidth = id == "name" ? 240 : id == "state" ? 100 : 180
            col.headerCell.font = .systemFont(ofSize: 11, weight: .medium); col.headerCell.textColor = .secondaryLabelColor; table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.delegate = self; table.dataSource = self; scroll.documentView = table
        table.registerForDraggedTypes([.fileURL]); table.target = self; table.doubleAction = #selector(showItem)
        card.contentView!.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: card.contentView!.leadingAnchor, constant: 1), scroll.trailingAnchor.constraint(equalTo: card.contentView!.trailingAnchor, constant: -1), scroll.topAnchor.constraint(equalTo: card.contentView!.topAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: card.contentView!.bottomAnchor, constant: -8)])
        let emptyIcon = NSImageView(image: NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)!)
        emptyIcon.contentTintColor = .tertiaryLabelColor; emptyIcon.symbolConfiguration = .init(pointSize: 29, weight: .light)
        emptyState.orientation = .vertical; emptyState.alignment = .centerX; emptyState.spacing = 12
        emptyState.addArrangedSubview(emptyIcon); emptyState.addArrangedSubview(label("还没有添加音乐", size: 14, color: .secondaryLabelColor)); emptyState.addArrangedSubview(label("拖入文件，或点击上方「选择文件」", size: 12, color: .tertiaryLabelColor))
        emptyState.translatesAutoresizingMaskIntoConstraints = false; card.contentView!.addSubview(emptyState)
        NSLayoutConstraint.activate([emptyState.centerXAnchor.constraint(equalTo: card.contentView!.centerXAnchor), emptyState.centerYAnchor.constraint(equalTo: card.contentView!.centerYAnchor, constant: 10)])
        location.lineBreakMode = .byTruncatingMiddle; location.font = .systemFont(ofSize: 12); location.textColor = .secondaryLabelColor
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chooseButton = button("更改", #selector(chooseOutput)); chooseButton.isBordered = false; chooseButton.contentTintColor = .systemTeal
        let folderIcon = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: "保存位置")!); folderIcon.contentTintColor = .secondaryLabelColor
        let out = horizontal([folderIcon, location, spacer(), chooseButton, button("打开文件夹", #selector(openOutput))]); out.spacing = 9
        stack.addArrangedSubview(out); out.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1; progress.style = .bar; progress.controlSize = .small
        stack.addArrangedSubview(progress); progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        message.lineBreakMode = .byTruncatingTail; message.font = .systemFont(ofSize: 12); message.textColor = .secondaryLabelColor
        startButton = button("开始转换", #selector(start)); startButton.bezelColor = .systemTeal; startButton.keyEquivalent = "\r"; startButton.controlSize = .large; startButton.font = .systemFont(ofSize: 14, weight: .semibold)
        startButton.widthAnchor.constraint(equalToConstant: 140).isActive = true
        stopButton = button("停止", #selector(stop))
        let actions = horizontal([message, spacer(), stopButton, startButton]); stack.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let foot = label("全程本地处理    ·    保留原文件    ·    输出原音频 MP3 / FLAC", size: 11, color: .tertiaryLabelColor)
        stack.addArrangedSubview(foot)
        refresh(); if !engineError.isEmpty { message.stringValue = engineError }; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let view = NSTextField(labelWithString: text); view.font = .systemFont(ofSize: size, weight: weight); view.textColor = color; return view
    }
    func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v }
    func horizontal(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = 10; return s
    }
    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; b.controlSize = .large; b.font = .systemFont(ofSize: 12, weight: .medium); b.setContentHuggingPriority(.required, for: .horizontal); return b
    }
    func refresh() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        location.stringValue = "保存到  " + output.path.replacingOccurrences(of: home + "/Desktop", with: "桌面").replacingOccurrences(of: home, with: "~")
        location.toolTip = output.path
        countLabel.stringValue = "转换列表 · \(entries.count) 首"
        emptyState.isHidden = !entries.isEmpty
        stopButton.isHidden = !busy
        addButton.isEnabled = !busy; clearButton.isEnabled = !busy; chooseButton.isEnabled = !busy
        startButton.isEnabled = !busy && !entries.isEmpty; startButton.bezelColor = startButton.isEnabled ? .systemTeal : .controlColor; stopButton.isEnabled = busy && !stopRequested
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
            var success = 0, failed = 0, report = "NCM转换器 2.1.0\n\(Date())\n保存到：\(folder.path)\n\n"
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
            DispatchQueue.main.async { self.busy = false; self.refresh(); self.message.stringValue = "\(self.stopRequested ? "已停止" : "处理完成")：成功 \(okCount) 个，需重新处理 \(badCount) 个。点击“打开文件夹”查看。" }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = entries[row], id = tableColumn?.identifier.rawValue ?? "name"
        let cell = NSView()
        if id == "name" {
            let icon = NSImageView(image: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!)
            icon.contentTintColor = .systemTeal; icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
            let name = label(item.url.deletingPathExtension().lastPathComponent, size: 13, weight: .medium)
            name.lineBreakMode = .byTruncatingMiddle; name.toolTip = item.url.path
            let folder = label(item.url.deletingLastPathComponent().lastPathComponent + "  ·  NCM", size: 11, color: .tertiaryLabelColor)
            let text = NSStackView(views: [name, folder]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 5
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let rowView = horizontal([icon, text]); rowView.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(rowView)
            NSLayoutConstraint.activate([rowView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), rowView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), rowView.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        } else if id == "state" {
            let tint: NSColor = item.state == "成功" ? .systemTeal : item.state == "需重新处理" ? .systemOrange : item.state == "转换中" ? .systemBlue : .secondaryLabelColor
            let text = item.state == "需重新处理" ? "需处理" : item.state
            let badge = NSBox(); badge.boxType = .custom; badge.titlePosition = .noTitle; badge.borderWidth = 0; badge.cornerRadius = 7; badge.fillColor = tint.withAlphaComponent(0.09); badge.translatesAutoresizingMaskIntoConstraints = false
            let value = label((item.state == "成功" ? "✓  " : "") + text, size: 11, weight: .medium, color: tint); value.translatesAutoresizingMaskIntoConstraints = false; badge.addSubview(value); badge.toolTip = item.detail
            cell.addSubview(badge)
            NSLayoutConstraint.activate([badge.leadingAnchor.constraint(equalTo: cell.leadingAnchor), badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor), badge.heightAnchor.constraint(equalToConstant: 25), badge.widthAnchor.constraint(equalToConstant: 80), value.centerXAnchor.constraint(equalTo: badge.centerXAnchor), value.centerYAnchor.constraint(equalTo: badge.centerYAnchor)])
        } else {
            var detail = item.detail
            if item.state == "成功" { let path = detail.replacingOccurrences(of: "成功：", with: ""); detail = "已保存为 " + URL(fileURLWithPath: path).pathExtension.uppercased() + "  ·  双击查看" }
            else if item.state == "待转换" { detail = "准备就绪" }
            let value = label(detail, size: 12, color: item.state == "需重新处理" ? .systemOrange : .secondaryLabelColor)
            value.lineBreakMode = .byTruncatingTail; value.toolTip = item.detail; value.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(value)
            NSLayoutConstraint.activate([value.leadingAnchor.constraint(equalTo: cell.leadingAnchor), value.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12), value.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        return cell
    }
    @objc func showItem() {
        let row = table.clickedRow; guard row >= 0 && row < entries.count else { return }
        let item = entries[row]
        if item.state == "成功" { let path = item.detail.replacingOccurrences(of: "成功：", with: ""); NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        else if !item.detail.isEmpty { let alert = NSAlert(); alert.messageText = item.url.lastPathComponent; alert.informativeText = item.detail; alert.beginSheetModal(for: window) }
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
