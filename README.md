# MacUnifiedUtility

# macOS Unified Utility App

## User Goal
Build a single macOS app to replace:
- Scroll Reverser
- Temperature monitoring app
- BatFi (battery charge limiting)
- BetterDisplay (display control)

---

## Initial Question
**User:** How can I build a macOS app to control:
- temperature probes
- screen resolution
- scroll reversing

### Key Answer
- ✅ Screen resolution → supported via Quartz Display Services
- ⚠️ Temperature probes → possible but requires low-level/private APIs (SMC)
- ❌ Global scroll reversing → no clean public API (requires event interception)

---

## Project Strategy

### Recommended Architecture
- SwiftUI menu bar + window app
- Modular design:
  - DisplayModule
  - ScrollingModule
  - ThermalModule
  - BatteryModule

### Tech Stack
- Swift + SwiftUI
- CoreGraphics (display)
- IOKit / event taps (input)
- SMC-based libs (thermal)

---

## Feature Feasibility

| Feature | Status |
|--------|-------|
| Display control | ✅ Easy |
| Scroll reversing | ⚠️ Medium (event taps) |
| Temperature monitoring | ⚠️ Medium/Hard (SMC) |
| Battery limit (80%) | ❗ Hard / unofficial |

---

## Recommended Development Order

### Phase 1
- Menu bar app
- Display resolution switching

### Phase 2
- Scroll reversing (mouse vs trackpad)

### Phase 3
- Temperature monitoring (read-only)

### Phase 4
- Battery limiting (experimental)

---

## Xcode Project Setup

### Template
- macOS → **App**

### Configuration
- Interface: SwiftUI
- Language: Swift
- Storage: None
- Testing: None (recommended)

---

## Menu Bar App Setup

### Basic MenuBarExtra

```swift
@main
struct AppName: App {
    var body: some Scene {
        MenuBarExtra("Control", systemImage: "gearshape") {
            Text("Hello")
        }
    }
}
