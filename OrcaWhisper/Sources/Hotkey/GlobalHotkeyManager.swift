import Foundation
import CoreGraphics
import AppKit
import os

final class GlobalHotkeyManager {
    private let logger = Logger(subsystem: "com.orca.whisper", category: "GlobalHotkey")

    var trigger: HotkeyTrigger = .singleModifier(.rightOption)
    let stateMachine: HotkeyStateMachine

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var isTriggerKeyDown = false

    init(stateMachine: HotkeyStateMachine) {
        self.stateMachine = stateMachine
    }

    func start() {
        stop()

        if setupEventTap() {
            logger.info("CGEventTap successfully installed for global hotkeys.")
        } else {
            logger.notice("CGEventTap creation returned nil. Falling back to NSEvent monitors.")
            setupNSEventMonitors()
        }
    }

    func ensureEventTapActive() {
        if eventTap == nil && PermissionsHelper.shared.isAccessibilityGranted() {
            logger.info("Accessibility permission detected. Upgrading to CGEventTap.")
            start()
        }
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func setupEventTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func setupNSEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Check for Escape key to cancel
        if keyCode == 53 { // Escape
            if type == .keyDown {
                if stateMachine.currentState != .idle {
                    stateMachine.handleEscape()
                    // Consume Escape so focused app doesn't trigger modal close
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        switch trigger {
        case .singleModifier(let targetModifier):
            if type == .flagsChanged {
                let match = targetModifier.matchesCGEvent(keyCode: keyCode, flags: event.flags)
                if match.isTargetKey {
                    processModifierPress(isPressed: match.isPressed)
                }
            }

        case .keyCombo(let requiredModifiers, let targetKeyCode, _):
            if keyCode == targetKeyCode {
                let flagsRaw = event.flags.rawValue
                let matchesModifiers = (flagsRaw & requiredModifiers) == requiredModifiers

                if type == .keyDown && matchesModifiers && !isTriggerKeyDown {
                    isTriggerKeyDown = true
                    stateMachine.handleKeyDown()
                    return nil
                } else if type == .keyUp && isTriggerKeyDown {
                    isTriggerKeyDown = false
                    stateMachine.handleKeyUp()
                    return nil
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleNSEvent(_ event: NSEvent) {
        let keyCode = event.keyCode

        if keyCode == 53 { // Escape
            if event.type == .keyDown && stateMachine.currentState != .idle {
                stateMachine.handleEscape()
            }
            return
        }

        switch trigger {
        case .singleModifier(let targetModifier):
            if event.type == .flagsChanged {
                let match = targetModifier.matchesNSEvent(event)
                if match.isTargetKey {
                    processModifierPress(isPressed: match.isPressed)
                }
            }

        case .keyCombo(let requiredModifiers, let targetKeyCode, _):
            if keyCode == targetKeyCode {
                let matchesModifiers = (UInt64(event.modifierFlags.rawValue) & requiredModifiers) == requiredModifiers
                if event.type == .keyDown && matchesModifiers && !isTriggerKeyDown {
                    isTriggerKeyDown = true
                    stateMachine.handleKeyDown()
                } else if event.type == .keyUp && isTriggerKeyDown {
                    isTriggerKeyDown = false
                    stateMachine.handleKeyUp()
                }
            }
        }
    }

    private func processModifierPress(isPressed: Bool) {
        if isPressed && !isTriggerKeyDown {
            isTriggerKeyDown = true
            stateMachine.handleKeyDown()
        } else if !isPressed && isTriggerKeyDown {
            isTriggerKeyDown = false
            stateMachine.handleKeyUp()
        }
    }
}

private extension CGEventFlags {
    func asNSEventModifierFlags() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.maskAlternate) { flags.insert(.option) }
        if contains(.maskCommand) { flags.insert(.command) }
        if contains(.maskControl) { flags.insert(.control) }
        if contains(.maskShift) { flags.insert(.shift) }
        if contains(.maskAlphaShift) { flags.insert(.capsLock) }
        if contains(.maskSecondaryFn) { flags.insert(.function) }
        return flags
    }
}
