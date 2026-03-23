import CoreGraphics
import Foundation

/// Manages global scroll-direction reversal for mouse and/or trackpad via a
/// `CGEvent` tap.
///
/// CGEvent taps intercept HID events system-wide and require **Accessibility**
/// permission (System Preferences → Privacy & Security → Accessibility).
/// If the permission is not granted the tap will silently fail to install.
///
/// Separate toggles let the user reverse only the mouse, only the trackpad,
/// or both independently.
@MainActor
final class ScrollManager: ObservableObject {

    // MARK: - Published State

    /// Whether scroll reversal is currently active (tap installed and running).
    @Published var isReversalActive = false

    /// Reverse scroll direction for mouse scroll wheels.
    @Published var reverseMouse = true {
        didSet { restartIfActive() }
    }

    /// Reverse scroll direction for trackpad scroll gestures.
    @Published var reverseTrackpad = false {
        didSet { restartIfActive() }
    }

    /// Non-nil when a user-facing error should be shown.
    @Published var lastError: String?

    // MARK: - Private State

    private var eventTap:    CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Store the current settings for use inside the C callback.
    private static var shared: ScrollManager?

    // MARK: - Init / Deinit

    init() {
        Self.shared = self
    }

    deinit {
        // deinit can't be @MainActor, so use a plain stop without the actor check.
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }

    // MARK: - Public API

    /// Install the CGEvent tap and start intercepting scroll events.
    func enable() {
        guard !isReversalActive else { return }
        lastError = nil

        guard PermissionsHelper.isAccessibilityEnabled(promptIfNeeded: true) else {
            lastError = "Accessibility permission is required. Enable it in System Settings → Privacy & Security → Accessibility."
            return
        }

        // Build the callback as a C closure.
        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            guard let manager = ScrollManager.shared else {
                return Unmanaged.passRetained(event)
            }
            return manager.handleEvent(type: type, event: event)
        }

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: callback,
            userInfo: nil
        )

        guard let tap else {
            lastError = "Could not create event tap. Ensure Accessibility is enabled."
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isReversalActive = true
    }

    /// Remove the CGEvent tap.
    func disable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        isReversalActive = false
    }

    func toggle() {
        isReversalActive ? disable() : enable()
    }

    // MARK: - Event Handling

    /// Called by the CGEvent tap callback for every intercepted scroll event.
    ///
    /// Returns the (possibly modified) event, or the original if no reversal applies.
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .scrollWheel else {
            return Unmanaged.passRetained(event)
        }

        let isTrackpad = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let shouldReverse = isTrackpad ? reverseTrackpad : reverseMouse

        if shouldReverse {
            // Reverse the primary scroll axis (vertical).
            let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)

            // Reverse the secondary scroll axis (horizontal) if non-zero.
            let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            if deltaX != 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -deltaX)
            }

            // For continuous (trackpad) events, also reverse the pixel deltas.
            if isTrackpad {
                let fixedPt1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedPt1)

                let fixedPt2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                if fixedPt2 != 0 {
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixedPt2)
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Private Helpers

    private func restartIfActive() {
        guard isReversalActive else { return }
        disable()
        enable()
    }
}
