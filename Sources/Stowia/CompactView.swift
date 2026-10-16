import SwiftUI
import AppKit
import ApplicationServices
import StowiaCore

/// The everyday interface, anchored to the menu bar. The library is optional.
struct CompactView: View {
    @ObservedObject var store: Store
    let openLibrary: () -> Void
    let openSettings: () -> Void
    let checkForUpdates: () -> Void
    let quit: () -> Void
    @ObservedObject private var updater: Updater

    init(store: Store, openLibrary: @escaping () -> Void, openSettings: @escaping () -> Void,
         checkForUpdates: @escaping () -> Void, quit: @escaping () -> Void) {
        self.store = store
        self.openLibrary = openLibrary
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        self.quit = quit
        updater = store.updater
    }
    @FocusState private var searchFocused: Bool
    @State private var canPaste = AXIsProcessTrusted()
    @State private var pendingDelete: Clip?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                StowiaMark().foregroundStyle(accent)
                Text(verbatim: "stowia").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Circle().fill(store.paused ? Color.gray : accent).frame(width: 5, height: 5)
                Group { if store.paused { Text("Paused") } else { Text("\(store.clips.count) clips") } }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your history…", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .accessibilityLabel("Search your history")
                if !store.query.isEmpty {
                    Button { store.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Clear Search")
                } else {
                    Text("⌘⇧V").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }.padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 12)

            HStack(spacing: 6) {
                filterChip("All", filter: .all)
                filterChip("Favorites", filter: .favorites, symbol: "star")
                Menu {
                    ForEach([ClipFilter.text, .link, .image, .file], id: \.self) { filter in
                        Button { store.filter = filter; searchFocused = true } label: { Label(filter.title, systemImage: filter.symbol) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isTypeFilter ? store.filter.title : String(localized: "Type"))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }.font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isTypeFilter ? accent : .secondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(isTypeFilter ? accent.opacity(0.12) : .clear, in: Capsule())
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                Spacer()
                if !store.query.isEmpty { Text("\(store.visibleClips.count) results").font(.system(size: 10)).foregroundStyle(.tertiary) }
            }.padding(.horizontal, 12).padding(.vertical, 10)
            Divider()

            if store.visibleClips.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: store.query.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                    Text(store.query.isEmpty ? (store.filter == .favorites ? "Your favorites live here." : "Nothing copied yet.") : "No results.")
                        .font(.system(size: 13, weight: .medium))
                    Text(store.query.isEmpty ? (store.filter == .favorites ? "Click the star next to a clip." : "Copy something and it shows up here.") : "Try another word or filter.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(store.visibleClips) { clip in
                                row(clip).id(clip.id)
                            }
                        }.padding(7)
                    }
                    .onChange(of: store.navigationSelection) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }

            if let clip = store.selectedClip, clip.displayKind == .image {
                Divider()
                VStack(spacing: 6) {
                    HStack {
                        Text("Image preview").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Enlarge", action: openLibrary).font(.system(size: 10)).buttonStyle(.plain)
                    }
                    if let image = store.previewImage {
                        Button(action: openLibrary) {
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity).frame(height: 116)
                                .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).help("Show the image in the library")
                    } else {
                        Label("The image couldn’t be previewed", systemImage: "photo")
                            .font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 50)
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10)
            }
            if let clip = store.selectedClip, store.compactDetailsVisible {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Full content").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.compactDetailsVisible = false
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        }.buttonStyle(.plain).help("Close Details")
                    }
                    ScrollView(.vertical) {
                        Text(clip.text.isEmpty ? clip.title : clip.text)
                            .font(.system(size: 11, design: .monospaced))
                            .lineSpacing(3).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading).padding(8)
                    }
                    .id(clip.id)
                    .frame(height: 104)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
            if let error = store.error {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3)
                    Spacer()
                    Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(10)
            } else if let notice = store.notice {
                Text(notice).font(.system(size: 10)).foregroundStyle(accent).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 8)
            }
            Divider()
            HStack(spacing: 12) {
                Menu {
                    if let title = Updater.menuTitle(updater.release, updater.status) {
                        Button(title, action: checkForUpdates)
                        Divider()
                    }
                    Button("Settings…", action: openSettings)
                    Button(store.paused ? "Resume Saving" : "Pause Saving") { store.togglePause() }.disabled(store.demo)
                    Button("Check for Updates…", action: checkForUpdates).disabled(store.demo)
                    Divider()
                    Button("Quit Stowia", action: quit)
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 12))
                        .overlay(alignment: .topTrailing) {
                            if updater.release != nil { Circle().fill(accent).frame(width: 5, height: 5).offset(x: 2, y: -1) }
                        }
                }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help(updater.release == nil ? String(localized: "Settings and saving") : String(localized: "An update is available"))
                Text(store.hotkeyAvailable ? (canPaste ? "⌘→ details · ↵ paste" : "⌘→ details · ↵ copy, then ⌘V") : "⌘⇧V is used by another app")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: openLibrary) { Image(systemName: "arrow.up.right.square").font(.system(size: 13)) }
                    .buttonStyle(.plain).help("Open Library").accessibilityLabel("Open Library")
            }.foregroundStyle(.secondary).padding(.horizontal, 15).frame(height: 36)
        }
        .frame(width: 380, height: 490)
        .background(canvas)
        .tint(accent)
        .onAppear { focusSearch() }
        .onChange(of: store.compactFocusRequest) { focusSearch() }
        .onChange(of: searchFocused) { store.compactSearchFocused = searchFocused }
        .onChange(of: store.query) { store.alignSelection() }
        .onChange(of: store.filter) { store.alignSelection() }
        .onChange(of: store.selection) { store.loadPreview() }
        .alert("Delete this clip?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let pendingDelete { store.delete(pendingDelete) }
                pendingDelete = nil
            }
        } message: {
            Text("“\(pendingDelete?.title ?? "")” will be deleted from your Stowia history.")
        }
    }

    private var isTypeFilter: Bool { store.filter != .all && store.filter != .favorites }
    private func focusSearch() {
        searchFocused = true
        store.compactSearchFocused = true
        // The demo shows the panel as it looks once pasting is allowed.
        canPaste = store.demo || AXIsProcessTrusted()
    }
    private func filterChip(_ title: LocalizedStringKey, filter: ClipFilter, symbol: String? = nil) -> some View {
        Button { store.filter = filter; searchFocused = true } label: {
            HStack(spacing: 4) { if let symbol { Image(systemName: symbol) }; Text(title) }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(store.filter == filter ? accent : .secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(store.filter == filter ? accent.opacity(0.12) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
    private func row(_ clip: Clip) -> some View {
        HStack(spacing: 0) {
            if clip.displayKind == .image {
                Button { store.selection = clip.id; store.loadPreview() } label: {
                    ClipThumbnail(clip: clip, store: store)
                        .frame(width: 44, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 9).padding(.trailing, 10)
                    .help("Preview Image").accessibilityLabel("Preview image: \(clip.title)")
            }
            Button {
                store.selection = clip.id
                store.useSelected()
            } label: {
                HStack(spacing: 10) {
                    if clip.displayKind != .image {
                        Image(systemName: clip.kind.symbol).font(.system(size: 13)).foregroundStyle(accent)
                            .frame(width: 29, height: 30).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clip.title).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                        HStack(spacing: 4) {
                            Text(clip.source).lineLimit(1)
                            Text("·")
                            Text(clip.copiedAt, style: .relative).lineLimit(1)
                        }.font(.system(size: 9)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, clip.displayKind == .image ? 0 : 9).padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { store.toggleFavorite(clip) } label: {
                Image(systemName: clip.favorite ? "star.fill" : "star")
                    .font(.system(size: 12)).foregroundStyle(clip.favorite ? accent : Color.secondary.opacity(0.6))
                    .frame(width: 32, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).help(clip.favorite ? "Remove from Favorites" : "Add to Favorites")
            Menu {
                Button("Copy") { store.onUse?(clip, false, false) }
                if clip.kind == .text || clip.kind == .link {
                    Button("Copy as Plain Text") { store.onUse?(clip, true, false) }
                }
                Button(clip.favorite ? "Remove from Favorites" : "Add to Favorites",
                       systemImage: clip.favorite ? "star.slash" : "star") { store.toggleFavorite(clip) }
                Button("Show Details", systemImage: "arrow.up.right.square") {
                    store.selection = clip.id
                    openLibrary()
                }
                Divider()
                Button("Delete…", systemImage: "trash", role: .destructive) { pendingDelete = clip }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 27, height: 44).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Clip Actions")
        }
        .background(store.selection == clip.id ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            if hovering {
                store.selection = clip.id
            }
        }
        .contextMenu {
            Button("Copy") { store.onUse?(clip, false, false) }
            if clip.kind == .text || clip.kind == .link { Button("Copy as Plain Text") { store.onUse?(clip, true, false) } }
            Button(clip.favorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(clip) }
            Divider()
            Button("Delete…", role: .destructive) { pendingDelete = clip }
            Button("Show Details") { store.selection = clip.id; openLibrary() }
        }
    }
}

private struct ClipThumbnail: View {
    let clip: Clip
    let store: Store
    @State private var thumbnail: NSImage?
    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 36)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: clip.id) { thumbnail = await store.image(for: clip, maxPixelSize: 96) }
    }
}
