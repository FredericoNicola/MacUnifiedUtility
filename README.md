# MacUnifiedUtility

A single **macOS menu bar app** replacing multiple standalone utilities:
- 🖥 **BetterDisplay** – screen resolution switching
- 🖱 **Scroll Reverser** – per-device scroll direction control
- 🌡 **Temperature Monitor** – SMC thermal sensor reading
- 🔋 **BatFi** – battery charge limiting (experimental)

---

## Features

| Feature | Status | Notes |
|---------|--------|-------|
| Display resolution switching | ✅ Implemented | Quartz Display Services / CoreGraphics public API |
| Scroll reversal (mouse & trackpad) | ✅ Implemented | CGEvent tap, requires Accessibility permission |
| Temperature monitoring | ✅ Implemented | Read-only SMC access via IOKit; ~40 keys covering Intel + Apple Silicon (M1/M2/M3/M4) |
| Battery charge limit (80%) | ⚠️ Experimental | SMC write (`BCLM` key) via SMJobBless helper tool (root), unofficial — use at own risk |

---

## Architecture

```
MacUnifiedUtility/
├── MacUnifiedUtilityApp.swift          ← @main entry, MenuBarExtra + Settings scene
└── Sources/
    ├── Modules/
    │   ├── Display/
    │   │   ├── DisplayManager.swift    ← CGDisplay enumeration & mode switching
    │   │   └── DisplayView.swift       ← SwiftUI view
    │   ├── Scrolling/
    │   │   ├── ScrollManager.swift     ← CGEvent tap installation/removal
    │   │   └── ScrollSettingsView.swift
    │   ├── Thermal/
    │   │   ├── SMCHelper.swift         ← Low-level SMC read via IOKit (Intel + Apple Silicon keys)
    │   │   ├── ThermalMonitor.swift    ← Observable polling monitor
    │   │   └── ThermalMonitorView.swift
    │   └── Battery/
    │       ├── BatteryManager.swift    ← IOKit Power Sources + SMC write (via helper)
    │       └── BatteryView.swift
    └── Shared/
        ├── SMCKit.swift                ← Shared SMC communication layer
        ├── PermissionsHelper.swift     ← Accessibility permission check/prompt
        ├── SharedViews.swift           ← Reusable SwiftUI components
        ├── PrivilegedSMCWriter.swift   ← SMC write dispatcher (unprivileged + helper)
        ├── PrivilegedHelperProtocol.swift ← XPC protocol shared by app and helper
        └── PrivilegedHelperManager.swift  ← SMJobBless installer + XPC client
HelperTool/
    ├── main.swift                      ← Privileged helper entry point (runs as root)
    ├── com.macunifiedutility.helper-Info.plist    ← Helper bundle info
    └── com.macunifiedutility.helper-Launchd.plist ← launchd service definition
```

### Tech Stack
- **Swift 5.9+** / **SwiftUI** (MenuBarExtra, Settings scene)
- **CoreGraphics** / Quartz Display Services (display)
- **CGEvent taps** (scroll reversal — requires Accessibility)
- **IOKit** / SMC (temperature monitoring, battery limiting)
- Swift Concurrency (`async/await`, `@MainActor`, `@Observable`)

---

## Requirements

| Requirement | Value |
|-------------|-------|
| macOS | 13.0 Ventura or later |
| Xcode | 15.0 or later |
| Swift | 5.9+ |
| App Sandbox | **Disabled** (required for IOKit / SMC access) |

---

## Build Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/FredericoNicola/MacUnifiedUtility.git
   cd MacUnifiedUtility
   ```

2. **Open in Xcode**
   ```bash
   open MacUnifiedUtility.xcodeproj
   ```

3. **Select your development team**
   - In Xcode → Project → Signing & Capabilities → Team

4. **Build & Run** (⌘R)

> **Note:** Sandbox is disabled in the entitlements file. Xcode may warn about
> this — this is intentional and required for SMC/IOKit access.

---

## Exporting & Installing the App

Since MacUnifiedUtility is not distributed via the App Store, you build and install it directly from Xcode.

### Prerequisites
- **Xcode 15+** installed from the Mac App Store or [developer.apple.com](https://developer.apple.com/xcode/).
- A free or paid **Apple Developer account** (a free account is sufficient for personal use).

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/FredericoNicola/MacUnifiedUtility.git
   cd MacUnifiedUtility
   ```

2. **Open the project in Xcode**
   ```
   open MacUnifiedUtility.xcodeproj
   ```

3. **Set your Development Team**
   - In Xcode, click the **MacUnifiedUtility** target → **Signing & Capabilities**.
   - Under *Team*, select your Apple ID / developer account.
   - Xcode will automatically manage provisioning profiles for local development.

4. **Build & Run on your Mac**
   - Select **My Mac** as the destination in the toolbar.
   - Press **⌘R** (or **Product → Run**). The app will launch in the menu bar.

5. **Archive for a standalone `.app`** (optional, so you can share/install without Xcode)
   - Go to **Product → Archive**.
   - When the Organizer opens, click **Distribute App**.
   - Choose **Copy App** (for personal/direct installation — no App Store or notarization needed).
   - Click **Export** and choose a folder. You'll get a `.app` bundle.
   - Drag the `.app` into `/Applications`.

6. **Allow the app to run (Gatekeeper)**
   If macOS blocks the app on first launch:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacUnifiedUtility.app
   ```
   Or go to **System Settings → Privacy & Security** and click **Open Anyway**.

> **Note:** The app requires the **HelperTool** (privileged helper) for SMC charging control. When running via Xcode (⌘R) this helper is automatically registered. For an exported `.app`, you may need to run it once from Xcode first so the helper is installed, or manually install the helper — see the [HelperTool README](HelperTool/) for details.

---

## Permissions

| Permission | Why Needed |
|------------|-----------|
| **Accessibility** | CGEvent tap for global scroll reversal |

The app will prompt for Accessibility access when scroll reversal is first enabled.
You can also grant it manually in **System Settings → Privacy & Security → Accessibility**.

---

## Development Phases

### ✅ Phase 1 – Menu bar app + Display resolution switching
- `@main` SwiftUI app with `MenuBarExtra`
- Display enumeration and mode switching via `CGDisplayCopyAllDisplayModes` / `CGDisplaySetDisplayMode`

### ✅ Phase 2 – Scroll reversing
- CGEvent tap intercepting `scrollWheel` events
- Independent toggles for mouse (discrete) vs trackpad (continuous) events

### ✅ Phase 3 – Temperature monitoring (read-only)
- IOKit connection to `AppleSMC` service
- Polls ~40 known SMC keys on a configurable timer covering Intel (`TC0P`, `TC0D`, `TG0D`, etc.) and Apple Silicon M1/M2/M3/M4 (`Tp09`, `Tp01`, `Tg05`, etc.)
- Dynamic CPU temperature summary checks Intel and Apple Silicon keys automatically

### ✅ Phase 4 – Battery limiting (experimental)
- IOKit Power Sources for real-time battery status
- Experimental SMC write to `BCLM` key (Battery Charge Level Maximum)
- Privileged helper tool (`com.macunifiedutility.helper`) installed via **SMJobBless**
  - Runs as root under launchd for reliable IOKit write access
  - XPC-based communication between app and helper
  - Helper is installed on demand when the user clicks "Install" in Battery view

---

## ⚠️ Disclaimer

- **SMC access** bypasses normal macOS security boundaries. This app runs without the App Sandbox, which is a deliberate trade-off for the required low-level access.
- **Battery charge limiting** writes to an **undocumented SMC key** (`BCLM`). This feature is experimental, may not work on all hardware, and is not supported by Apple.
- This project is provided **as-is** for educational and personal use. The author is not responsible for any damage to your hardware or data.
