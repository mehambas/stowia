import SwiftUI
import AppKit
import ApplicationServices
import StowiaCore
import UniformTypeIdentifiers

let accent = Color(white: 0.92)
let canvas = Color(white: 0.055)

/// The menu bar icon, also used as the app's mark inside its windows. A bare `swift build` has no resources to load it from.
struct StowiaMark: View {
    var size: CGFloat = 16
    var body: some View {
        if let image = NSImage(named: "MenuBarIconTemplate") {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: "square.on.square").font(.system(size: size * 0.8))
        }
    }
}

// The hidden library must not lay out full clipboard contents while the quick panel is used.
struct LibraryHostView: View {
    @ObservedObject var store: Store
    var body: some View {
        if store.libraryVisible {
            MainView(store: store)
        } else {
            canvas
        }
    }
}

struct MainView: View {
    @ObservedObject var store: Store
    @FocusState private var searchFocused: Bool
    @State private var pendingDelete: Clip?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    searchBar
                    Divider()
                    HStack(spacing: 0) {
                        history.frame(width: 350)
                        Divider()
                        preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            Divider()
            footer
        }
        .background(canvas)
        .tint(accent)
        .frame(minWidth: 920, minHeight: 540)
        .onAppear { searchFocused = true; store.alignSelection() }
        .onChange(of: store.focusRequest) { searchFocused = true }
        .onChange(of: searchFocused) { store.searchFocused = searchFocused }
        .onChange(of: store.query) { store.alignSelection() }
        .onChange(of: store.filter) { store.alignSelection() }
        .onChange(of: store.selection) { store.loadPreview() }
        .sheet(isPresented: $store.settingsVisible) { SettingsView(store: store) }
        .alert("Delete this favorite?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { if let clip = pendingDelete { store.delete(clip) }; pendingDelete = nil }
        } message: { Text("This favorite will be deleted for good.") }
        .alert(Text(verbatim: "Stowia"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                StowiaMark(size: 22)
                    .foregroundStyle(.white).frame(width: 38, height: 38).background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "stowia").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.8)
                    Text("Copy. Find. Use.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 33)
            Text("LIBRARY").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary).padding(.leading, 10).padding(.bottom, 10)
            ForEach([ClipFilter.all, .favorites], id: \.self) { filter in filterButton(filter) }
            Text("CONTENT TYPE").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary).padding(.leading, 10).padding(.top, 27).padding(.bottom, 10)
            ForEach([ClipFilter.text, .link, .image, .file], id: \.self) { filter in filterButton(filter) }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) { Circle().fill(store.paused ? Color.gray : accent).frame(width: 6, height: 6)
                    Text(store.demo ? "Demo mode" : store.paused ? "Saving is paused" : "Watching the clipboard").font(.system(size: 11, weight: .medium)) }
                Text("Kept on this Mac only.").font(.system(size: 10)).foregroundStyle(.secondary)
                Button { store.togglePause() } label: {
                    Label(store.paused ? "Resume Saving" : "Pause Saving", systemImage: store.paused ? "play" : "pause")
                        .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(.top, 4).disabled(store.demo)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            Button { store.settingsVisible = true } label: {
                HStack { Image(systemName: "gearshape"); Text("Settings"); Spacer(); Text(verbatim: "⌘,").foregroundStyle(.tertiary) }
                    .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 16)
            }.buttonStyle(.plain).keyboardShortcut(",", modifiers: .command)
        }.padding(.horizontal, 16).padding(.top, 20).frame(width: 196)
            .background(accent.opacity(0.025))
    }
    private func filterButton(_ filter: ClipFilter) -> some View {
        let active = store.filter == filter
        return Button { store.filter = filter } label: {
            HStack(spacing: 10) {
                Image(systemName: filter.symbol).frame(width: 18)
                Text(filter.title)
                Spacer()
                Text("\(store.clips.filter { filter.includes($0) }.count)").font(.system(size: 10, weight: .medium, design: .monospaced)).opacity(0.65)
            }.font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? accent : Color.primary.opacity(0.75))
                .padding(.horizontal, 11).padding(.vertical, 11)
                .background(active ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.bottom, 3)
    }
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(accent)
            TextField("Search your history…", text: $store.query).textFieldStyle(.plain).font(.system(size: 16)).focused($searchFocused)
                .accessibilityLabel("Search your history")
            if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            Text(verbatim: "⌘ ⇧ V").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
        }.padding(.horizontal, 25).frame(height: 74)
    }
    private var history: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.filter.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(store.visibleClips.count) clips").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 17)
            if store.visibleClips.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: store.query.isEmpty ? "square.on.square.dashed" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(accent.opacity(0.6))
                    Text(store.query.isEmpty ? "There’s room here." : "No results.").font(.system(size: 15, weight: .medium))
                    Text(emptyMessage).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.visibleClips) { clip in
                                ClipRow(clip: clip, selected: store.selection == clip.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { store.selection = clip.id }
                                    .contextMenu {
                                        Button("Copy") { store.onUse?(clip, false, false) }
                                        if clip.kind == .text || clip.kind == .link { Button("Copy as Plain Text") { store.onUse?(clip, true, false) } }
                                        Button(clip.favorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(clip) }
                                        Divider()
                                        Button("Delete", role: .destructive) { remove(clip) }
                                    }.id(clip.id)
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 12)
                    }.onChange(of: store.navigationSelection) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }
    private var emptyMessage: LocalizedStringKey {
        if !store.query.isEmpty { return "Try another word or content type." }
        if store.filter == .favorites { return "Click the star on the clips you want to keep. Favorites are never deleted automatically." }
        if store.filter != .all { return "Copy something of this type and it shows up here." }
        return "Copy some text, a link, an image or a file. Stowia remembers it here."
    }
    @ViewBuilder private var preview: some View {
        if let clip = store.selectedClip {
            DetailView(clip: clip, image: store.previewImage, rename: { store.rename(clip, to: $0) }, favorite: { store.toggleFavorite(clip) },
                       copy: { store.useSelected(paste: false) }, paste: { store.useSelected(plain: $0) }, delete: { remove(clip) },
                       reveal: { store.revealFile(clip) }, saveImage: { store.saveImage(clip) })
                .id(clip.id)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(accent.opacity(0.5))
                Text("Right at hand.").font(.system(size: 24, weight: .medium, design: .serif))
                Text("What you just copied,\nor that little note you always need.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var footer: some View {
        HStack(spacing: 18) {
            if let notice = store.notice { Text(notice) }
            else if store.hotkeyAvailable { Text("↑ ↓  move     ↵  paste     ⇧ ↵  plain text") }
            else { Text("⌘⇧V isn’t available. Open Stowia from the menu bar.") }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(store.totalBytes), countStyle: .file))
            Text("esc  close")
        }.font(.system(size: 10)).foregroundStyle(store.notice == nil ? Color.secondary : accent)
            .padding(.horizontal, 20).frame(height: 34)
    }
    private func remove(_ clip: Clip) { if clip.favorite { pendingDelete = clip } else { store.delete(clip) } }
}

private struct ClipRow: View {
    let clip: Clip
    let selected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
                Image(systemName: clip.displayKind.symbol).font(.system(size: 14)).foregroundStyle(selected ? accent : .secondary)
                .frame(width: 33, height: 35).background(selected ? accent.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 7) {
                Text(clip.title).font(.system(size: 12, weight: .medium)).lineLimit(2).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text(clip.source).lineLimit(1)
                    Text("·")
                    Text(clip.copiedAt, style: .relative).lineLimit(1)
                    Spacer(minLength: 0)
                    if clip.favorite { Image(systemName: "star.fill").foregroundStyle(accent) }
                }.font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? accent.opacity(0.24) : .clear, lineWidth: 1))
    }
}

private struct DetailView: View {
    let clip: Clip
    let image: NSImage?
    let rename: (String) -> Void
    let favorite: () -> Void
    let copy: () -> Void
    let paste: (Bool) -> Void
    let delete: () -> Void
    let reveal: () -> Void
    let saveImage: () -> Void
    @State private var name = ""
    @FocusState private var editingName: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(clip.displayKind.title.uppercased(), systemImage: clip.displayKind.symbol).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(accent)
                Spacer()
                Button(action: favorite) { Image(systemName: clip.favorite ? "star.fill" : "star").foregroundStyle(clip.favorite ? accent : .secondary) }
                    .help(clip.favorite ? "Remove from Favorites" : "Add to Favorites").accessibilityLabel(clip.favorite ? "Remove from Favorites" : "Add to Favorites")
                Menu {
                    if clip.kind == .link, let url = URL(string: clip.text) { Button("Open in Browser") { NSWorkspace.shared.open(url) } }
                    if clip.kind == .file { Button("Show in Finder", action: reveal) }
                    if clip.displayKind == .image { Button("Save Image…", action: saveImage) }
                    Button("Delete", role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            }.buttonStyle(.plain).font(.system(size: 15)).padding(.bottom, 22)
            TextField("Name this clip…", text: $name).textFieldStyle(.plain)
                .font(.system(size: 19, weight: .semibold)).focused($editingName)
                .onSubmit { rename(name); editingName = false }
                .onChange(of: editingName) { _, focused in if !focused && name != clip.name { rename(name) } }
                .onDisappear { if name != clip.name { rename(name) } }
                .padding(.bottom, 10)
            HStack(spacing: 7) {
                Text(clip.source)
                Text("·")
                Text(clip.copiedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 22)
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if clip.displayKind == .image, let image {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 420, maxHeight: 350).padding(18)
                    } else {
                        Text(clip.text).font(.system(size: 12, design: .monospaced)).lineSpacing(7).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading).padding(18)
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
            HStack {
                if clip.favorite { Label("Never deleted automatically", systemImage: "pin.fill") }
                else if clip.isImageFile { Text("Stowia keeps the image’s location, not a copy of the file.") }
                else if clip.kind == .file { Text("Stowia keeps the file’s location, not a copy of the file.") }
                else { Text("\(clip.text.count) characters") }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(clip.byteCount), countStyle: .file))
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 15)
            HStack(spacing: 10) {
                Button(action: copy) { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(.vertical, 7) }.buttonStyle(.bordered)
                Button { paste(false) } label: { HStack { Text("Paste"); Spacer(); Text(verbatim: "↵").opacity(0.6) }.padding(.vertical, 7).padding(.horizontal, 5) }
                    .buttonStyle(.borderedProminent).foregroundStyle(.black)
            }.font(.system(size: 12, weight: .medium))
            if clip.kind == .text || clip.kind == .link {
                Button { paste(true) } label: { Text("Paste as Plain Text  ⇧↵").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                    .buttonStyle(.plain).padding(.top, 12)
            }
        }.padding(25).onAppear { name = clip.name }
    }
}

private struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject private var updater: Updater
    @Environment(\.dismiss) private var dismiss
    @State private var excluded: [String] = []
    @State private var confirmClear = false
    @State private var clearHour = false
    @State private var trusted = AXIsProcessTrusted()

    init(store: Store) {
        self.store = store
        updater = store.updater
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Stowia Settings").font(.system(size: 23, weight: .semibold)); Spacer(); Button("Done") { save(); dismiss() }.keyboardShortcut(.defaultAction) }
            Form {
                Section("History") {
                    Picker("Keep clips for", selection: $store.preferences.retentionDays) {
                        ForEach([1, 7, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) }
                    }
                    Picker("Maximum clips", selection: $store.preferences.maxItems) {
                        ForEach([100, 500, 1000, 5000], id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    Picker("History size", selection: $store.preferences.maxMegabytes) {
                        ForEach([50, 200, 500, 1000], id: \.self) { Text(verbatim: "\($0) MB").tag($0) }
                    }
                    Text("Favorites don’t count toward these limits. A single copy can be up to 25 MB.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Pasting") {
                    HStack {
                        Label(trusted ? "Accessibility access is on" : "Automatic pasting is off", systemImage: trusted ? "checkmark.circle" : "keyboard")
                        Spacer()
                        Button("Allow Access…") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            trusted = AXIsProcessTrustedWithOptions(options)
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                    Text("Without it, the history and copying still work: paste with ⌘V in the other app. Open Stowia with ⌘⇧V.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("Nothing copied from these apps is saved.").font(.caption)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(excluded, id: \.self) { bundle in
                                HStack {
                                    Text(appName(bundle))
                                    Spacer()
                                    Button { excluded.removeAll { $0 == bundle } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.plain).help("Remove from the List")
                                }.font(.system(size: 12))
                            }
                        }.padding(6)
                    }.frame(height: 88)
                    Button("Add App…") { chooseExcludedApp() }
                    if let clip = store.selectedClip, !clip.sourceBundle.isEmpty {
                        Button("Exclude \(clip.source)") {
                            let bundle = clip.sourceBundle
                            if !excluded.contains(bundle) { excluded.append(bundle) }
                        }
                    }
                    Text("Content that apps mark as concealed or transient, such as passwords, is never saved. An app that doesn’t mark its secrets can still have them saved. Excluding an app affects only new copies.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Clear Last Hour…", role: .destructive) { clearHour = true; confirmClear = true }
                        Button("Clear History…", role: .destructive) { clearHour = false; confirmClear = true }
                    }
                    Text("Clearing keeps your favorites. Clearing Stowia’s history doesn’t clear the clipboard.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.automatic).disabled(store.demo)
                    UpdateRow(updater: updater)
                    Text("Once a day Stowia asks GitHub for the latest version number. Nothing about you or your clipboard is sent.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack {
                Text("Stowia \(updater.current.description) · Everything stays on this Mac.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit Stowia") {
                    save(); dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        NSApp.terminate(nil)
                    }
                }
            }
        }.padding(25).frame(width: 610, height: 690).background(canvas).tint(accent)
            .onAppear { excluded = store.preferences.excludedBundles }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
            .onDisappear { save() }
            .alert(clearHour ? "Delete the last hour’s clips?" : "Clear the history?", isPresented: $confirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { store.clear(since: clearHour ? Date().addingTimeInterval(-3600) : nil) }
            } message: { Text("Your favorites are kept. Everything else is deleted for good.") }
    }
    private func save() {
        store.preferences.excludedBundles = Array(Set(excluded)).sorted()
        store.savePreferences()
    }
    private func appName(_ bundle: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return ["com.agilebits.onepassword7": "1Password 7", "com.1password.1password": "1Password", "com.bitwarden.desktop": "Bitwarden",
                "com.apple.Passwords": String(localized: "Passwords")][bundle] ?? bundle
    }
    private func chooseExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Exclude")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundle = Bundle(url: url)?.bundleIdentifier, !excluded.contains(bundle) { excluded.append(bundle) }
        }
    }
}

private struct UpdateRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if let release = updater.release, let version = release.version {
            LabeledContent {
                Button("Download and Install") { updater.install() }
                    .disabled(busy)
                    .help("Downloads the disk image and opens it, then Stowia quits so you can drag the new version to Applications.")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stowia \(version.description) is available")
                    switch updater.status {
                    case .downloading(let fraction):
                        ProgressView(value: fraction).accessibilityLabel("Downloading Stowia \(version.description)").frame(height: 14)
                    case .opening:
                        detail("Drag Stowia from the disk image to Applications and replace this version.")
                    case .failed(let reason):
                        warning(reason)
                    default:
                        HStack(spacing: 4) {
                            detail("You have \(updater.current.description).")
                            Link("Release Notes", destination: release.page).font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            LabeledContent {
                Button("Check Now") { updater.check(manual: true) }.disabled(updater.status == .checking)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Stowia \(updater.current.description)")
                    switch updater.status {
                    case .checking: detail("Checking for updates…")
                    case .upToDate: detail("This is the latest version.")
                    case .checkFailed(let reason): warning(String(localized: "Couldn’t check for updates. \(reason)"))
                    default:
                        if let lastCheck = updater.lastCheck {
                            detail("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        } else {
                            detail("Not checked yet.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var busy: Bool {
        switch updater.status {
        case .downloading, .opening: return true
        default: return false
        }
    }

    private func detail(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }
}
