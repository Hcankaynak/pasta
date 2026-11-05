import AppKit
import SwiftUI
import Combine
import Carbon

/// UI state shared between the popover view and the keyboard handler.
final class PopoverState: ObservableObject {
    @Published var query = ""
    @Published var filter: ClipFilter = .all
    @Published var selectedID: UUID?
    @Published var focusToken = 0
    @Published var now = Date()
    @Published var quip = Quips.random()

    var terms: [String] { query.split(whereSeparator: { $0.isWhitespace }).map(String.init) }

    func prepareForShow() {
        query = ""
        filter = .all
        selectedID = nil
        now = Date()
        quip = Quips.random()
        focusToken += 1
    }

    /// `nil` selection means "the first visible row".
    func isSelected(_ item: ClipItem, in items: [ClipItem]) -> Bool {
        (selectedID ?? items.first?.id) == item.id
    }

    func selected(in items: [ClipItem]) -> ClipItem? {
        if let id = selectedID, let item = items.first(where: { $0.id == id }) { return item }
        return items.first
    }

    func move(_ delta: Int, in items: [ClipItem]) {
        guard !items.isEmpty else { return }
        let current = selected(in: items)?.id
        let idx = items.firstIndex(where: { $0.id == current }) ?? 0
        let next = max(0, min(items.count - 1, idx + delta))
        selectedID = items[next].id
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = ClipboardStore()
    let ui = PopoverState()
    private let keys = ShortcutCenter.shared

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var iconTask: Task<Void, Never>?
    private var iconStyle: IconStyle = IconStyle.current
    private var cancellables = Set<AnyCancellable>()

    private enum IconMood { case idle, newClip, picked }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setIcon(.idle)

        let root = ContentView(
            onPick: { [weak self] item in self?.pick(item) },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        .environmentObject(store)
        .environmentObject(ui)

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: ContentView.width, height: ContentView.height)
        popover.contentViewController = NSHostingController(rootView: root)

        store.onNewClip = { [weak self] in self?.flash(.newClip) }
        store.$isPaused
            .sink { [weak self] paused in self?.statusItem.button?.alphaValue = paused ? 0.4 : 1.0 }
            .store(in: &cancellables)
        store.start()

        // Re-read the icon style whenever settings change.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let style = IconStyle.current
                if style != self.iconStyle {
                    self.iconStyle = style
                    self.setIcon(.idle)
                }
            }
            .store(in: &cancellables)

        // Global "Open Pasta" shortcut — re-registered whenever it's edited,
        // and paused while a new shortcut is being recorded.
        let hk = HotKey()
        hk.action = { [weak self] in self?.togglePopover() }
        hotKey = hk
        Publishers.CombineLatest(keys.$map, keys.$recordingAction)
            .sink { [weak self] map, recording in
                self?.hotKey?.register(recording == nil ? map[.openPasta] : nil)
            }
            .store(in: &cancellables)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover.isShown else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// A hidden main menu so standard keys (⌘C, ⌘V, ⌘A, ⌘W, ⌘Q) work in text fields and windows.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Pasta", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        let pause = NSMenuItem(title: store.isPaused ? "Resume Saving Copies" : "Pause Saving Copies",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Pasta", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePause() { store.isPaused.toggle() }
    @objc private func openSettingsFromMenu() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Popover

    func togglePopover() {
        if popover.isShown { closePopover(restoreFocus: true) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }

        ui.prepareForShow()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover(restoreFocus: Bool) {
        popover.performClose(nil)
        if restoreFocus, let prev = previousApp, !prev.isTerminated {
            prev.activate(options: [])
        }
    }

    // MARK: Settings window

    func openSettings() {
        if popover.isShown { popover.performClose(nil) }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.title = "Pasta Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        keys.stopRecording()
    }

    // MARK: Actions

    private func pick(_ item: ClipItem) {
        store.copy(item)
        flash(.picked)
        closePopover(restoreFocus: true)

        if UserDefaults.standard.bool(forKey: "autoPaste") {
            if Accessibility.isTrusted {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    Accessibility.paste()
                }
            } else {
                Accessibility.request()
            }
        }
    }

    private func visibleItems() -> [ClipItem] {
        store.search(ui.query, filter: ui.filter, sort: ClipSort.current)
    }

    /// Keyboard control while the popover is open — every key here comes from Settings.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === popover.contentViewController?.view.window else { return false }
        let items = visibleItems()
        let map = keys.map
        func hit(_ action: ShortcutAction) -> Bool { map[action]?.matches(event) ?? false }

        if hit(.copySelected) {
            if let item = ui.selected(in: items) { pick(item) }
            return true
        }
        if hit(.moveDown) { ui.move(1, in: items); return true }
        if hit(.moveUp) { ui.move(-1, in: items); return true }
        if hit(.togglePin) {
            if let item = ui.selected(in: items) { store.togglePin(item) }
            return true
        }
        if hit(.deleteItem) {
            if let item = ui.selected(in: items) {
                let idx = items.firstIndex(of: item) ?? 0
                store.delete(item)
                let remaining = visibleItems()
                ui.selectedID = remaining.isEmpty ? nil : remaining[min(idx, remaining.count - 1)].id
            }
            return true
        }
        if hit(.clearOrClose) {
            if !ui.query.isEmpty { ui.query = "" } else { closePopover(restoreFocus: true) }
            return true
        }
        if hit(.openSettings) {
            openSettings()
            return true
        }

        // Quick copy: modifier + 1…9
        if keys.quickCopy != .off,
           event.modifierFlags.intersection(Shortcut.relevantFlags) == keys.quickCopy.flags,
           let idx = KeyNames.digitCodes.firstIndex(of: event.keyCode) {
            if idx < items.count { pick(items[idx]) }
            return true
        }
        return false
    }

    // MARK: Menu bar icon

    private func setIcon(_ mood: IconMood) {
        guard let button = statusItem.button else { return }
        switch iconStyle {
        case .colorful:
            button.image = nil
            button.imagePosition = .noImage
            switch mood {
            case .idle: button.title = "🍝"
            case .newClip: button.title = ["✨", "🤌", "😋", "🧀"].randomElement() ?? "✨"
            case .picked: button.title = "😋"
            }
        case .classic:
            // The same bowl of spaghetti, drawn in monochrome. It's a template image,
            // so it follows the light/dark menu bar like system icons.
            let iconMood: PastaIcon.Mood
            switch mood {
            case .idle: iconMood = .idle
            case .newClip: iconMood = .sparkle
            case .picked: iconMood = .happy
            }
            let image = PastaIcon.image(pointSize: 18, mood: iconMood)
            button.title = ""
            button.image = image
            button.imagePosition = .imageOnly
        }
        let open = keys.map[.openPasta].map { " (\($0.display))" } ?? ""
        button.toolTip = "Pasta — clipboard history" + open
    }

    private func flash(_ mood: IconMood) {
        setIcon(mood)
        iconTask?.cancel()
        iconTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }
            self?.setIcon(.idle)
        }
    }
}
