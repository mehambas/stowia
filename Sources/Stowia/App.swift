import AppKit
import SwiftUI
import Carbon
import ApplicationServices
import StowiaCore

final class StowiaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@main struct StowiaApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    var panel: StowiaPanel!
    var compactPanel: QuickPanel!
    var store: Store!
    private var previousApp: NSRunningApplication?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var compactWindow: NSWindow? { compactPanel }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory: URL
        if demo {
            try? FileManager.default.removeItem(at: Self.demoDirectory)
            directory = Self.demoDirectory
        } else {
            directory = support.appendingPathComponent("Stowia")
            SaklaMigration.run(from: support.appendingPathComponent("Sakla"), to: directory,
                               oldDefaults: UserDefaults(suiteName: SaklaMigration.oldDomain), newDefaults: UserDefaults.standard)
        }
        store = Store(directory: directory, demo: demo)
        store.onUse = { [weak self] clip, plain, paste in self?.use(clip, plain: plain, paste: paste) }
        buildMenu()
        panel = StowiaPanel(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 670),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Stowia"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 920, height: 580)
        if !demo { panel.setFrameAutosaveName("StowiaMainWindow") }
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LibraryHostView(store: store))
        panel.center()
        compactPanel = QuickPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 490),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        compactPanel.title = String(localized: "Stowia Quick Search")
        compactPanel.isOpaque = false
        compactPanel.backgroundColor = .clear
        compactPanel.hasShadow = true
        compactPanel.level = .statusBar
        compactPanel.hidesOnDeactivate = false
        compactPanel.isReleasedWhenClosed = false
        compactPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        compactPanel.contentView = NSHostingView(rootView: CompactView(
            store: store,
            openLibrary: { [weak self] in self?.showLibrary() },
            openSettings: { [weak self] in self?.showSettings() },
            checkForUpdates: { [weak self] in self?.checkForUpdates() },
            quit: { [weak self] in self?.quit() }
        ).clipShape(RoundedRectangle(cornerRadius: 13)))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if !demo { statusItem.autosaveName = "com.hamzabasaran.stowia.menubar" }
        let statusImage = NSImage(named: "MenuBarIconTemplate") ?? NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        statusImage?.isTemplate = true
        statusImage?.accessibilityDescription = "Stowia"
        statusItem.button?.image = statusImage
        statusItem.button?.toolTip = String(localized: "Stowia · Clipboard history (⌘⇧V)")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated {
                self?.previousApp = app
                self?.compactPanel.orderOut(nil)
            }
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissCompactIfOutside(NSEvent.mouseLocation) }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Menus belong to Stowia too; let their action finish before dismissing.
            if let self, event.window === self.panel { self.compactPanel.orderOut(nil) }
            return event
        }
        if CommandLine.arguments.contains("--capture-demo") {
            Task { @MainActor in await self.captureDemo() }
            return
        }
        registerHotkey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window, window.isKeyWindow,
                  (window === self.panel || window === self.compactWindow),
                  !self.store.settingsVisible, window.attachedSheet == nil else { return event }
            let isCompact = window === self.compactWindow
            let isEditing = (window.firstResponder as? NSTextView)?.isFieldEditor == true
            let isSearch = isCompact ? self.store.compactSearchFocused : self.store.searchFocused
            if isCompact && event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                self.showSettings(); return nil
            }
            switch event.keyCode {
            case 53:
                if isCompact { self.compactPanel.orderOut(nil) } else { self.panel.orderOut(nil) }
                return nil
            case 125 where !isEditing || isSearch: self.store.moveSelection(1); return nil
            case 126 where !isEditing || isSearch: self.store.moveSelection(-1); return nil
            case UInt16(kVK_RightArrow) where isCompact && event.modifierFlags.contains(.command):
                self.store.compactDetailsVisible.toggle()
                return nil
            case 36 where !isEditing || isSearch:
                self.store.useSelected(plain: event.modifierFlags.contains(.shift)); return nil
            default: return event
            }
        }
        showCompact()
        if CommandLine.arguments.contains("--self-check") {
            Task { @MainActor in await self.runSelfCheck() }
        }
        store.updater.start()
    }
    private var demo: Bool { ["--demo", "--capture-demo"].contains(where: CommandLine.arguments.contains) }
    private static let demoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Stowia Demo")
    func applicationWillTerminate(_ notification: Notification) {
        if demo { try? FileManager.default.removeItem(at: Self.demoDirectory) }
    }
    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        let quitItem = appMenu.addItem(withTitle: String(localized: "Quit Stowia"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appItem.submenu = appMenu; main.addItem(appItem)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: String(localized: "Edit"))
        for (title, action, key) in [(String(localized: "Cut"), "cut:", "x"), (String(localized: "Copy"), "copy:", "c"),
                                     (String(localized: "Paste"), "paste:", "v"), (String(localized: "Select All"), "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
    }
    private func registerHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data -> OSStatus in
            guard let data else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.toggle() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: 0x53544F57, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotkey)
        store.hotkeyAvailable = result == noErr
    }
    @objc private func toggle() {
        if compactPanel.isVisible { compactPanel.orderOut(nil) } else { showCompact() }
    }
    private func rememberPreviousApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
    }
    func showCompact() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        rememberPreviousApp()
        if store.settingsVisible { panel.makeKeyAndOrderFront(nil); return }
        panel.orderOut(nil)
        store.libraryVisible = false
        // Both windows share one store. Preserve the active search and selection when
        // switching from the library back to the menu-bar panel.
        store.alignSelection()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(anchor.midX - 190, visible.minX + 8), visible.maxX - 388)
        let y = max(visible.minY + 8, min(anchor.minY - 496, visible.maxY - 496))
        compactPanel.setFrameOrigin(NSPoint(x: x, y: y))
        compactPanel.makeKeyAndOrderFront(nil)
        store.compactFocusRequest = UUID()
    }
    private func dismissCompactIfOutside(_ point: NSPoint) {
        guard compactPanel.isVisible, !compactPanel.frame.contains(point) else { return }
        if let button = statusItem.button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        compactPanel.orderOut(nil)
    }
    func showLibrary() {
        rememberPreviousApp()
        compactPanel.orderOut(nil)
        store.libraryVisible = true
        store.alignSelection(); store.focusRequest = UUID()
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    private func showSettings() {
        showLibrary()
        store.settingsVisible = true
    }
    private func checkForUpdates() {
        if store.updater.release == nil { store.updater.check(manual: true) }
        showSettings()
    }
    @objc private func quit() {
        compactPanel.orderOut(nil)
        store.settingsVisible = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            NSApp.terminate(nil)
        }
    }
    private func hideInterfaces() { compactPanel.orderOut(nil); panel.orderOut(nil); store.libraryVisible = false }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if sender === panel { store.libraryVisible = false }
        return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showCompact(); return true }
    private func use(_ clip: StowiaCore.Clip, plain: Bool, paste: Bool) {
        guard store.copy(clip, plain: plain) else { return }
        let expectedChange = NSPasteboard.general.changeCount
        guard paste else { store.showNotice(String(localized: "Copied to the clipboard")); return }
        guard let previousApp, !previousApp.isTerminated else { store.showNotice(String(localized: "Copied. Paste it with ⌘V.")); return }
        guard AXIsProcessTrusted() else {
            store.showNotice(String(localized: "Copied. To paste automatically, allow Accessibility access in Settings."))
            hideInterfaces(); previousApp.activate(options: [])
            return
        }
        hideInterfaces(); previousApp.activate(options: [])
        Task { @MainActor in
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard NSPasteboard.general.changeCount == expectedChange else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp.processIdentifier else { continue }
                // Let the key that opened the panel finish before synthesizing a paste.
                let flags = CGEventSource.flagsState(.combinedSessionState)
                guard !flags.contains(.maskCommand), !flags.contains(.maskShift), !flags.contains(.maskAlternate), !flags.contains(.maskControl) else { continue }
                let source = CGEventSource(stateID: .privateState)
                let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
                down?.flags = .maskCommand; up?.flags = .maskCommand
                down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
                return
            }
            self.store.showNotice(String(localized: "Copied. Paste it with ⌘V."))
        }
    }

    // Isolated preview verification: never reads or writes the general pasteboard.
    private func runSelfCheck() async {
        guard store.demo else { return }
        if GitHubReleases.testing { store.updater.check(manual: true) }
        try? await Task.sleep(nanoseconds: 700_000_000)
        var checks: [String: Bool] = [:]
        checks["compactIsDefault"] = compactPanel.isVisible && !panel.isVisible
        checks["compactSize"] = compactPanel.frame.width == 380 && compactPanel.frame.height == 490
        store.query = "git history"
        store.alignSelection()
        checks["searchByName"] = store.visibleClips.count == 1 && store.selectedClip?.text.hasPrefix("git log") == true
        if let clip = store.selectedClip {
            let wasFavorite = clip.favorite
            store.toggleFavorite(clip)
            checks["favoriteToggle"] = store.selectedClip?.favorite == !wasFavorite
            if let updated = store.selectedClip { store.toggleFavorite(updated) }
        }
        store.query = ""; store.filter = .favorites; store.alignSelection()
        checks["favoritesFilter"] = store.visibleClips.count == 3 && store.visibleClips.allSatisfy(\.favorite)
        store.filter = .all; store.alignSelection()
        let before = store.selection
        checks["searchFocused"] = store.compactSearchFocused && compactWindow?.isKeyWindow == true
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: compactWindow?.windowNumber ?? 0,
                                       context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
                                       isARepeat: false, keyCode: 125) {
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        checks["arrowKeyNavigation"] = store.selection != before
        checks["hotkeyRegistered"] = store.hotkeyAvailable
        store.selection = store.clips.first(where: { $0.name == "Git history" })?.id
        try? await Task.sleep(nanoseconds: 300_000_000)
        let output = URL(fileURLWithPath: CommandLine.arguments.last ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if let view = compactPanel.contentView { capture(view, to: output.appendingPathComponent("compact.png")) }
        if let clip = store.clips.first(where: { $0.kind == .image }) {
            store.filter = .image
            store.selection = clip.id
            store.loadPreview()
            checks["imageThumbnail"] = await store.image(for: clip, maxPixelSize: 96) != nil
            try? await Task.sleep(nanoseconds: 200_000_000)
            checks["imagePreview"] = store.previewImage != nil
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let view = compactPanel.contentView { capture(view, to: output.appendingPathComponent("compact-image.png")) }
        } else { checks["imagePreview"] = false }
        store.filter = .all; store.alignSelection()
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: compactWindow?.windowNumber ?? 0,
                                       context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                       isARepeat: false, keyCode: 53) { NSApp.postEvent(event, atStart: false) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        checks["escapeClosesCompact"] = !compactPanel.isVisible
        showCompact()
        try? await Task.sleep(nanoseconds: 200_000_000)
        checks["compactReopens"] = compactPanel.isVisible
        checks["reopenedSearchFocused"] = store.compactSearchFocused && compactPanel.isKeyWindow
        dismissCompactIfOutside(NSPoint(x: compactPanel.frame.minX - 20, y: compactPanel.frame.minY))
        checks["outsideClickDismissal"] = !compactPanel.isVisible
        showCompact()
        store.selection = store.clips.first(where: { $0.name == "Git history" })?.id
        let librarySelection = store.selection
        showLibrary()
        try? await Task.sleep(nanoseconds: 300_000_000)
        checks["libraryKeepsSelection"] = !compactPanel.isVisible && panel.isKeyWindow && store.selection == librarySelection
        capturePreview(to: output.appendingPathComponent("preview.png"))
        store.settingsVisible = true
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let sheet = panel.attachedSheet, let view = sheet.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("settings.png"))
            if GitHubReleases.testing { checks["updateOffered"] = store.updater.release != nil }
            if let scroll = Self.scrollView(in: view), let document = scroll.documentView {
                document.scroll(NSPoint(x: 0, y: document.isFlipped ? document.bounds.maxY : 0))
                try? await Task.sleep(nanoseconds: 300_000_000)
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("settings-end.png"))
            }
        }
        try? JSONEncoder().encode(checks).write(to: output.appendingPathComponent("checks.json"))
        store.settingsVisible = false
        try? await Task.sleep(nanoseconds: 400_000_000)
        NSApp.terminate(nil)
    }
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView?.bounds.height ?? 0 > scroll.contentSize.height { return scroll }
        return view.subviews.lazy.compactMap(scrollView(in:)).first
    }
    private func capturePreview(to url: URL) {
        guard let view = panel.contentView else { return }
        capture(view, to: url)
    }
    func capture(_ view: NSView, to url: URL) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
