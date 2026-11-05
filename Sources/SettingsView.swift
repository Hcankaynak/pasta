import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutView()
                .tabItem { Label("About", systemImage: "fork.knife") }
        }
        .frame(width: 560, height: 560)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var store: ClipboardStore

    @AppStorage("sortOrder") private var sort: ClipSort = .lastUsed
    @AppStorage("iconStyle") private var iconStyle: IconStyle = .colorful
    @AppStorage("historyLimit") private var historyLimit = ClipboardStore.unlimited
    @AppStorage("autoPaste") private var autoPaste = false

    @State private var launchAtLogin = false
    @State private var axTrusted = Accessibility.isTrusted
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Picker("Icon style", selection: $iconStyle) {
                    ForEach(IconStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                iconPreview
            } header: {
                Text("Appearance")
            } footer: {
                Text("Classic uses a monochrome menu bar icon that matches the rest of macOS.")
            }

            Section("Startup") {
                Toggle("Launch Pasta at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
            }

            Section {
                Picker("Sort history by", selection: $sort) {
                    ForEach(ClipSort.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                Picker("Keep up to", selection: $historyLimit) {
                    ForEach(ClipboardStore.historyLimitOptions, id: \.self) { n in
                        Text(n == ClipboardStore.unlimited ? "Unlimited" : "\(n) items").tag(n)
                    }
                }
                Toggle("Pause saving new copies", isOn: $store.isPaused)
                HStack {
                    Text("\(store.items.count) items in the pot")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear History…") { confirmClear = true }
                }
            } header: {
                Text("History")
            } footer: {
                Text("“Last used” puts anything you copied or picked recently at the top. “Date created” keeps the order you first copied things in. Pinned items always stay on top.")
            }

            Section {
                Toggle("Paste directly after picking an item", isOn: $autoPaste)
                if autoPaste && !axTrusted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Pasta needs Accessibility permission to paste for you.")
                            .font(.callout)
                        Spacer()
                        Button("Open Settings") { Accessibility.openSystemSettings() }
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                Text("When this is off, Pasta copies the item and switches back to your app. Then just press ⌘V.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            axTrusted = Accessibility.isTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            axTrusted = Accessibility.isTrusted
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: historyLimit) { _ in store.applyLimit() }
        .onChange(of: autoPaste) { on in
            if on && !Accessibility.isTrusted { Accessibility.request() }
            axTrusted = Accessibility.isTrusted
        }
        .alert("Drain the pot?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every item except your pinned ones will be removed. This can't be undone.")
        }
    }

    private var iconPreview: some View {
        HStack(spacing: 14) {
            Text("Preview").foregroundColor(.secondary)
            Spacer()
            if iconStyle == .colorful {
                Text("🍝").font(.system(size: 16))
            } else {
                PastaGlyph(size: 18)
            }
            ForEach([ClipKind.url, .code, .multiline, .email, .number], id: \.self) { kind in
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconStyle == .colorful ? kind.tint.opacity(0.16) : Color.primary.opacity(0.07))
                    Image(systemName: kind.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(kind.tint(iconStyle))
                }
                .frame(width: 26, height: 26)
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Pasta: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsView: View {
    @ObservedObject private var center = ShortcutCenter.shared

    var body: some View {
        Form {
            Section {
                row(.openPasta)
            } header: {
                Text("Everywhere")
            } footer: {
                Text("Works from any app. Needs ⌘, ⌥ or ⌃ (or an F-key).")
            }

            Section {
                ForEach(ShortcutAction.allCases.filter { !$0.isGlobal }) { action in
                    row(action)
                }
                Picker("Quick copy items 1–9", selection: $center.quickCopy) {
                    ForEach(QuickCopyModifier.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
            } header: {
                Text("While Pasta is open")
            }

            Section {
                HStack {
                    Text("Click a shortcut, then press the new keys. Click it again to cancel.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Restore Defaults") { center.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { center.stopRecording() }
    }

    private func row(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                    if let detail = action.detail {
                        Text(detail).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                ShortcutRecorder(action: action)
            }
            if center.recordingAction == action, let error = center.recordingError {
                Text(error).font(.caption).foregroundColor(.red)
            } else if let other = center.conflict(for: action) {
                Text("Same keys as “\(other)”. Only one of them will work.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var store: ClipboardStore
    @AppStorage("iconStyle") private var iconStyle: IconStyle = .colorful
    @State private var spin: Double = 0

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Group {
                if iconStyle == .colorful {
                    Text("🍝").font(.system(size: 72))
                } else {
                    PastaGlyph(size: 72)
                }
            }
            .rotationEffect(.degrees(spin))
            .onTapGesture {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.5)) { spin += 360 }
            }
            Text("Pasta")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text("paste + fun")
                .foregroundColor(.secondary)
            Text("Version \(version)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 30) {
                stat("\(store.totalCopies)", "copies served")
                stat("\(store.items.count)", "in the pot")
                stat("\(store.pinnedCount)", "pinned")
            }
            .padding(.top, 14)

            Button("Show History File in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
            }
            .padding(.top, 14)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}
