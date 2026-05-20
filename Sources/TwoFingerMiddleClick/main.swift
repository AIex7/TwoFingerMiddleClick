import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import TouchBridge

private final class TouchActivityState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTouchFrameTime: CFAbsoluteTime?
    private var lastFingerCount = 0

    func recordTouchFrame(fingerCount: Int) {
        lock.withLock {
            lastTouchFrameTime = CFAbsoluteTimeGetCurrent()
            lastFingerCount = fingerCount
        }
    }

    func recentFingerCountAge() -> (count: Int, age: TimeInterval)? {
        lock.withLock {
            guard let lastTouchFrameTime else {
                return nil
            }

            return (lastFingerCount, CFAbsoluteTimeGetCurrent() - lastTouchFrameTime)
        }
    }
}

private final class RightClickToMiddleClickConverter {
    private let touchActivityState: TouchActivityState
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shouldSuppressRightMouseUp = false
    private var lastPostTime = CFAbsoluteTimeGetCurrent()
    private let minimumInterval: TimeInterval = 0.08
    private let liveTouchPassThroughWindow: TimeInterval = 0.08

    init(touchActivityState: TouchActivityState) {
        self.touchActivityState = touchActivityState
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let converter = Unmanaged<RightClickToMiddleClickConverter>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                return converter.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else {
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        shouldSuppressRightMouseUp = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .rightMouseDown {
            let recentTouch = touchActivityState.recentFingerCountAge()
            let shouldPassThrough = recentTouch.map {
                $0.count >= 2 && $0.age <= liveTouchPassThroughWindow
            } ?? false

            if shouldPassThrough {
                shouldSuppressRightMouseUp = false
                return Unmanaged.passUnretained(event)
            }

            shouldSuppressRightMouseUp = true
            postMiddleClick(at: event.location)
            return nil
        }

        if type == .rightMouseUp, shouldSuppressRightMouseUp {
            shouldSuppressRightMouseUp = false
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func postMiddleClick(at point: CGPoint) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastPostTime >= minimumInterval else {
            return
        }
        lastPostTime = now

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .otherMouseDown,
            mouseCursorPosition: point,
            mouseButton: .center
        )
        down?.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .otherMouseUp,
            mouseCursorPosition: point,
            mouseButton: .center
        )
        up?.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        up?.post(tap: .cghidEventTap)
    }
}

private final class TouchFrameMonitor {
    private var running = false

    func start() throws {
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let ok = TFMCStartMultitouch({ count, _ in
            guard count >= 0 else {
                return
            }

            Task { @MainActor in
                AppDelegate.shared?.touchActivityState.recordTouchFrame(fingerCount: Int(count))
            }
        }, &errorBuffer, errorBuffer.count)

        if !ok {
            let message = errorBuffer.withUnsafeBufferPointer { buffer in
                let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
                let bytes = buffer[..<end].map { UInt8(bitPattern: $0) }
                return String(decoding: bytes, as: UTF8.self)
            }
            throw NSError(
                domain: "TwoFingerMiddleClick.TouchFrameMonitor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        running = true
    }

    func stop() {
        guard running else {
            return
        }

        TFMCStopMultitouch()
        running = false
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static weak var shared: AppDelegate?

    let touchActivityState = TouchActivityState()
    lazy var rightClickConverter = RightClickToMiddleClickConverter(
        touchActivityState: touchActivityState
    )
    let touchFrameMonitor = TouchFrameMonitor()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        requestAccessibilityIfNeeded()

        if !rightClickConverter.start() {
            NSLog("TwoFingerMiddleClick could not start the right-click conversion event tap.")
        }

        do {
            try touchFrameMonitor.start()
            statusMenuItem.title = "Right click converts to middle click"
        } catch {
            statusMenuItem.title = "Touch monitor failed"
            showError(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchFrameMonitor.stop()
        rightClickConverter.stop()
    }

    private func configureMenu() {
        statusItem.button?.title = "2F"
        statusItem.button?.toolTip = "Two Finger Middle Click"

        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusItem.menu = statusMenu
    }

    private func requestAccessibilityIfNeeded() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Two Finger Middle Click could not start"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
