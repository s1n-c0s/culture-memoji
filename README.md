# Culture Memoji (Memoji Studio)

A native macOS Swift application to access, render, interact with, and export **Apple System Memojis & Animojis**.

![Memoji Studio](AppIcon.icns)

## Features

- **Apple System Memoji Sync**:
  - Directly queries your macOS / iCloud personal Memoji database (`~/Library/Application Support/Animoji/CoreDataBackend/avatars.db`).
  - Reads pre-rendered high-res transparent PNG stickers (`~/Library/Application Support/Animoji/Stickers/`).
- **Apple Built-in Animojis**:
  - Browse and render all 27 built-in Apple characters (`fox`, `panda`, `unicorn`, `dragon`, `robot`, `alien`, `cat`, `dog`, `lion`, `tiger`, etc.).
- **Interactive 3D Stage (AvatarKit)**:
  - Real-time 3D SceneKit / VFX viewport powered by Apple's native `AVTView`.
  - Orbit, pan, and view your Memoji from any angle with real Apple shading and physics dynamics.
  - Live pose animation: click any sticker expression (Heart Eyes, Mind Blown, Kiss, Thumbs Up, Peace, etc.) to smoothly animate the 3D model into that pose in real time.
- **Live Camera Face-Tracking Mirror**:
  - Live face-tracking mode (`AVTRecordView`) using your Mac's camera to mirror your facial expressions (smiles, blinks, eyebrow raises, mouth movements) directly onto your Memoji!
- **3D Random Memoji Generator**:
  - Create completely new, randomized 3D Memojis on the fly with a single click.
- **Sticker Gallery & Search**:
  - Browse 70+ sticker expressions organized by categories: *All*, *Expressions*, *Gestures*, *Reactions*, *Activities*.
  - Instant live keyword search (e.g. `love`, `kiss`, `cry`, `party`, `peace`, `thumbs up`, `mac`).
- **Export & Sharing Studio**:
  - **One-Click Copy**: Copies transparent PNGs directly to clipboard for pasting into Messages, Telegram, Slack, Discord, Notes, or Figma.
  - **Drag and Drop**: Drag any sticker directly from the app window into other applications or Finder folders.
  - **Custom Export**: Choose custom resolutions (256px icon, 512px standard, 1024px HD, 2048px Ultra HD), background colors (Transparent, White, Dark, Sunset, Ocean, Pastel Violet, Neon Mint), and formats (PNG, JPEG).
  - **Batch Export**: Export entire packs of stickers to a folder on disk in one go.
  - **Native macOS Share Sheet**: AirDrop, Messages, Mail, etc.
- **System Settings Integration**:
  - Direct shortcut to open macOS System Settings to customize or design new Memojis.

---

## Requirements

- **macOS 14.0+** (Sonoma, Sequoia, or later)
- Swift 6.0+
- Apple Silicon (M1/M2/M3/M4) or Intel Mac

---

## Quick Start

### 1. Run directly with Swift Package Manager:
```bash
swift run CultureMemoji
```

### 2. Build the Standalone macOS App (`.app`):
```bash
./bundle_app.sh
open CultureMemoji.app
```

---

## Architecture

- **`AvatarKitBridge.swift`**: Dynamic runtime bridge interfacing with Apple's private `AvatarKit.framework`, `AvatarKitContent.framework`, and `AvatarPersistence.framework`. Provides safe loading, scene management, snapshot rendering, and pose animations.
- **`AvatarDatabaseReader.swift`**: Direct SQLite integration reading user Memoji definitions and matching them to on-disk sticker PNG assets.
- **`StickerExportManager.swift`**: Handles clipboard operations, custom background compositing, NSSavePanel file dialogs, and batch file writing.
- **`Views/`**: Clean, modular SwiftUI views built for macOS with NavigationSplitView, unified toolbars, and `NSViewRepresentable` wrappers.