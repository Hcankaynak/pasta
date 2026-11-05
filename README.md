# 🍝 Pasta

**paste + fun = pasta.** A small, fast clipboard history app for your Mac's menu bar.

Copy text anywhere and Pasta keeps it. Click 🍝 in the menu bar (or press **⇧⌘V** from any app) to see your history, search it, and copy anything back.

## Build & install

You need Apple's Command Line Tools (one-time setup):

```bash
xcode-select --install
```

Then from this folder:

```bash
chmod +x build.sh
./build.sh install
```

This builds `Pasta.app`, copies it to `/Applications` and launches it. Look for 🍝 in your menu bar.
To build without installing, run `./build.sh`, then `open build/Pasta.app`.

> First launch: if macOS says the app "can't be opened", right-click **Pasta.app** in Applications, choose **Open**, then **Open** again.

## Features

- **Runs in the background.** It has no Dock icon and lives only in the menu bar.
- **Saves every text you copy**, with the app it came from and when you copied it. If you copy the same text again, it moves back to the top.
- **Instant search.** Type to filter. Several words narrow the results (`git push`), and matches are highlighted. You can also search by app name ("Safari") or pasta shape ("Spaghetti").
- **Pasta shapes.** Each item is sorted by what it contains:

  | Shape | What it is |
  |---|---|
  | 🔗 Ravioli | Links (with an *Open link* button) |
  | 💻 Spaghetti | Code (shown in a monospaced font) |
  | 📚 Lasagna | Multi-line text |
  | 🎨 Rotini | Hex colors (with a color swatch) |
  | ✉️ Farfalle | Email addresses |
  | 🔢 Orzo | Numbers |
  | 📝 Penne | Everything else |

- **Filter chips** across the top: All, Pinned, or one shape.
- **Pin favorites.** Pinned items stay at the top and are never removed automatically.
- **Season It.** Right-click an item to copy it as UPPERCASE, lowercase or Title Case, with whitespace trimmed, or joined into one line.
- **Privacy aware.** Pasta skips anything an app marks as concealed or temporary, which is how most password managers flag copied passwords. History is stored only on your Mac, at `~/Library/Application Support/Pasta/history.json`.
- **Sorting.** Sort by *Last used* (anything you copy or pick jumps to the top) or *Date created* (the order you first copied things). Change it in Settings or with the ⇅ button next to the search field.
- **Pause** saving at any time: use the ⏸ button, or right-click the menu bar icon.
- **Little delights.** The menu bar icon reacts when something new is copied (✨ 🤌 😋 🧀). Click the big 🍝 in the header to give it a twirl.

## Settings

Open Settings with the ⚙︎ button, ⌘, inside Pasta, or by right-clicking the menu bar icon.

- **General**
  - Icon style: **Colorful** (🍝 and colored pasta icons) or **Classic** (a monochrome menu bar icon that matches macOS, with grey icons inside the app)
  - Launch at login
  - Sort order and how many items to keep (5, 25, 100 or Unlimited)
  - Pause saving, and clear history
  - Paste directly after picking
- **Shortcuts.** Every shortcut can be changed, including the one that opens Pasta. Click a shortcut, then press the new keys. Each shortcut has a ✕ to remove it and a ↺ to restore its default, and *Restore Defaults* resets them all. Pasta warns you if two shortcuts use the same keys.
- **About.** Version, your stats, and a button that shows the history file in Finder.

## Keyboard shortcuts (defaults)

| Keys | Action |
|---|---|
| ⇧⌘V | Open or close Pasta from anywhere |
| ↑ / ↓ | Move the selection |
| ↩ | Copy the selected item and return to your app |
| ⌘1 … ⌘9 | Quickly copy item 1–9 |
| ⌘P | Pin or unpin the selected item |
| ⌘⌫ | Delete the selected item |
| Esc | Clear the search, then close |
| ⌘, | Open Settings |

After you pick an item, Pasta closes and returns you to the app you were using, so you just press ⌘V.
To skip that step, turn on **Paste Directly After Picking**. macOS will then ask you to give Pasta Accessibility permission. Because this is a self-built (unsigned) app, you may need to grant the permission again after each rebuild.

## Mac App Store build (Xcode)

`Pasta.xcodeproj` builds the same app from the same `Sources/` folder, set up for the Mac App Store:
App Sandbox on, Hardened Runtime on, the app icon in `AppStore/Assets.xcassets`, and "no encryption" declared.

1. Open `Pasta.xcodeproj` in Xcode.
2. Select the **Pasta** target → **Signing & Capabilities** → choose your **Team**.
3. **Product → Run** to test the sandboxed build, then **Product → Archive** → **Distribute App** → **App Store Connect**.

`build.sh` still works for quick local builds. New `.swift` files added to `Sources/` are picked up by both.
The `docs/` folder holds the privacy policy, support page and home page, ready for GitHub Pages.

## Project layout

```
Sources/
  main.swift            app entry point (menu bar only, no Dock icon)
  AppDelegate.swift     menu bar icon, popover, global hotkey, keyboard control
  ClipboardStore.swift  clipboard watcher, history, search, saving to disk
  ContentView.swift     the popover interface
  SettingsView.swift    Settings window (General, Shortcuts, About)
  Shortcuts.swift       editable shortcuts: storage, recorder, key names
  Models.swift          clip item, pasta shapes, sorting, icon style, highlighting
  System.swift          global hotkey (Carbon) and auto-paste helper
Resources/Info.plist
AppStore/              Xcode assets, entitlements and Info.plist for the App Store build
docs/                  privacy policy, support and home pages (for GitHub Pages)
Pasta.xcodeproj
build.sh
```

Requires macOS 13 (Ventura) or newer.
