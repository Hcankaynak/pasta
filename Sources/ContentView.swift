import SwiftUI
import AppKit

struct ContentView: View {
    static let width: CGFloat = 400
    static let height: CGFloat = 560

    @EnvironmentObject var store: ClipboardStore
    @EnvironmentObject var ui: PopoverState
    @ObservedObject private var keys = ShortcutCenter.shared

    let onPick: (ClipItem) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var spin: Double = 0
    @AppStorage("sortOrder") private var sort: ClipSort = .lastUsed
    @AppStorage("iconStyle") private var iconStyle: IconStyle = .colorful

    private var colorful: Bool { iconStyle == .colorful }

    var body: some View {
        let items = store.search(ui.query, filter: ui.filter, sort: sort)
        VStack(spacing: 0) {
            header
            searchBar
            filterChips
            Divider()
            content(items)
            Divider()
            footer
        }
        .frame(width: ContentView.width, height: ContentView.height)
        .onAppear { searchFocused = true }
        .onChange(of: ui.focusToken) { _ in searchFocused = true }
        .onChange(of: ui.query) { _ in ui.selectedID = nil }
        .onChange(of: ui.filter) { _ in ui.selectedID = nil }
        .onChange(of: sort) { _ in ui.selectedID = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if colorful {
                    Text("🍝").font(.system(size: 28))
                } else {
                    PastaGlyph(size: 30)
                }
            }
            .rotationEffect(.degrees(spin))
            .onTapGesture {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) { spin += 360 }
                ui.quip = Quips.random()
            }
            .help("Twirl!")

            VStack(alignment: .leading, spacing: 1) {
                Text("Pasta")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text(store.isPaused ? "Kitchen closed — new copies aren't saved" : ui.quip)
                    .font(.system(size: 11))
                    .foregroundColor(store.isPaused ? .orange : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.isPaused.toggle()
            } label: {
                Image(systemName: store.isPaused ? "play.circle.fill" : "pause.circle")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help(store.isPaused ? "Resume saving copies" : "Pause saving copies")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help(settingsHelp)
            .contextMenu {
                Button("Settings…") { onOpenSettings() }
                Button("Quit Pasta") { onQuit() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var settingsHelp: String {
        if let s = keys.map[.openSettings] { return "Settings (\(s.display))" }
        return "Settings"
    }

    // MARK: Search, sort & filters

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search your noodles…", text: $ui.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !ui.query.isEmpty {
                Button { ui.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(ClipSort.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sorted by: \(sort.label)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 12)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(.all, title: "All", count: store.items.count, tint: .accentColor)
                if store.pinnedCount > 0 {
                    chip(.pinned, title: colorful ? "📌 Pinned" : "Pinned", count: store.pinnedCount,
                         tint: colorful ? .orange : .accentColor)
                }
                ForEach(store.kindCounts) { kc in
                    chip(.kind(kc.kind), title: kc.kind.label, count: kc.count,
                         tint: colorful ? kc.kind.tint : .accentColor)
                        .help(kc.kind.pastaName)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ filter: ClipFilter, title: String, count: Int, tint: Color) -> some View {
        let active = ui.filter == filter
        return Button {
            ui.filter = filter
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .foregroundColor(active ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(active ? Color.white : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(active ? tint : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    @ViewBuilder
    private func content(_ items: [ClipItem]) -> some View {
        if store.items.isEmpty {
            emptyState(colorful ? "🍝" : nil, symbol: "doc.on.clipboard", "The pot is empty", emptyHint)
        } else if items.isEmpty {
            emptyState(colorful ? "🔍" : nil, symbol: "magnifyingglass", "No noodles match",
                       ui.query.isEmpty ? "Nothing in this category yet." : "Nothing found for “\(ui.query)”.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipRow(item: item,
                                    index: index,
                                    terms: ui.terms,
                                    selected: ui.isSelected(item, in: items),
                                    now: ui.now,
                                    sort: sort,
                                    style: iconStyle,
                                    quickSymbol: keys.quickCopy.symbol,
                                    onPick: onPick)
                                .id(item.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: ui.selectedID) { id in
                    if let target = id ?? items.first?.id {
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(target) }
                    }
                }
            }
        }
    }

    private var emptyHint: String {
        var s = "Copy some text anywhere and it'll start cooking here."
        if let open = keys.map[.openPasta] { s += "\nOpen Pasta any time with \(open.display)." }
        return s
    }

    private func emptyState(_ emoji: String?, symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            if let emoji = emoji {
                Text(emoji).font(.system(size: 46))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.secondary)
            }
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(colorful ? "🍝 \(store.totalCopies) served" : "\(store.totalCopies) served")
            Spacer()
            Text(hints)
                .lineLimit(1)
        }
        .font(.system(size: 10.5))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var hints: String {
        var parts: [String] = []
        if let s = keys.map[.copySelected] { parts.append("\(s.display) copy") }
        if let q = keys.quickCopy.symbol { parts.append("\(q)1–9 quick") }
        if let s = keys.map[.togglePin] { parts.append("\(s.display) pin") }
        if let s = keys.map[.deleteItem] { parts.append("\(s.display) delete") }
        return parts.joined(separator: "   ")
    }
}

// MARK: - Row

struct ClipRow: View {
    @EnvironmentObject var store: ClipboardStore

    let item: ClipItem
    let index: Int
    let terms: [String]
    let selected: Bool
    let now: Date
    let sort: ClipSort
    let style: IconStyle
    let quickSymbol: String?
    let onPick: (ClipItem) -> Void

    @State private var hovering = false

    private var tint: Color { item.kind.tint(style) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Highlighter.text(item.preview, terms: terms)
                    .font(.system(size: 12.5, design: item.kind == .code ? .monospaced : .default))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                meta
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.20)
                               : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onPick(item) }
        .help(item.tooltip)
        .contextMenu { contextItems }
    }

    private var meta: Text {
        var parts: [String] = []
        if let app = item.appName { parts.append(app) }
        switch sort {
        case .lastUsed: parts.append(RelTime.string(item.date, now: now))
        case .created: parts.append("added " + RelTime.string(item.createdAt, now: now))
        }
        parts.append(item.sizeLabel)
        if item.copyCount > 1 { parts.append("×\(item.copyCount)") }
        return Text(item.kind.pastaName).foregroundColor(tint).fontWeight(.semibold)
            + Text("  " + parts.joined(separator: " · "))
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(style == .colorful ? item.kind.tint.opacity(0.16) : Color.primary.opacity(0.07))
            if item.kind == .color, let c = ClipKind.rgb(from: item.text) {
                // The swatch shows the copied color itself, so it stays in color in both styles.
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: c.r, green: c.g, blue: c.b))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                    .padding(5)
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var trailing: some View {
        Group {
            if hovering {
                HStack(spacing: 2) {
                    if item.kind == .url, let url = linkURL {
                        iconButton("arrow.up.right.square", help: "Open link") { NSWorkspace.shared.open(url) }
                    }
                    iconButton(item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Unpin" : "Pin") {
                        store.togglePin(item)
                    }
                    iconButton("trash", help: "Delete") {
                        withAnimation(.easeOut(duration: 0.15)) { store.delete(item) }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(style == .colorful ? .orange : .secondary)
                    }
                    if index < 9, let q = quickSymbol {
                        Text("\(q)\(index + 1)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 44, alignment: .trailing)
    }

    private var linkURL: URL? {
        var s = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("www.") { s = "https://" + s }
        return URL(string: s)
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder
    private var contextItems: some View {
        Button("Copy") { onPick(item) }
        Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
        Menu("Season It (Copy Transformed)") {
            Button("UPPERCASE") { season { $0.uppercased() } }
            Button("lowercase") { season { $0.lowercased() } }
            Button("Title Case") { season { $0.capitalized } }
            Button("Trim Whitespace") { season { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            Button("Join Into One Line") {
                season { text in
                    text.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }
            }
        }
        if let url = linkURL, item.kind == .url {
            Button("Open Link") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(item) }
    }

    private func season(_ transform: (String) -> String) {
        let newText = transform(item.text)
        guard !newText.isEmpty else { return }
        let newItem = store.add(text: newText, appName: item.appName, bundleID: item.bundleID)
        onPick(newItem)
    }
}
