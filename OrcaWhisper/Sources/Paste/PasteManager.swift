import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import os

struct SavedPasteboardEntry {
    let types: [NSPasteboard.PasteboardType]
    let dataMap: [NSPasteboard.PasteboardType: Data]
}

final class PasteManager {
    static let shared = PasteManager()
    private let logger = Logger(subsystem: "com.orca.whisper", category: "PasteManager")

    private init() {}

    func deliver(
        text: String,
        targetApp: NSRunningApplication? = nil,
        deliveryMode: DeliveryMode = .paste,
        restoreClipboard: Bool = true,
        restoreDelayMs: Double = 300.0,
        addTrailingSpace: Bool = false,
        addTrailingNewline: Bool = false,
        prefixText: String = "",
        suffixText: String = ""
    ) {
        var final = text
        if !prefixText.isEmpty {
            final = prefixText + final
        }
        if !suffixText.isEmpty {
            final = final + suffixText
        }
        if addTrailingSpace {
            final = final + " "
        }
        if addTrailingNewline {
            final = final + "\n"
        }

        guard !final.isEmpty else { return }

        // Reactivate target application if it was active before dictation
        if let target = targetApp, target != NSRunningApplication.current {
            logger.info("Activating target application for insertion: \(target.localizedName ?? "unknown", privacy: .public)")
            target.activate()
        }

        let isTargetAlreadyFront = (targetApp == nil || targetApp == NSWorkspace.shared.frontmostApplication)
        let switchDelay = isTargetAlreadyFront ? 0.05 : 0.15

        // Brief delay to ensure macOS window server routes keyboard focus to target
        DispatchQueue.main.asyncAfter(deadline: .now() + switchDelay) { [weak self] in
            guard let self = self else { return }
            if deliveryMode == .typeDirectly {
                self.typeText(final, targetApp: targetApp)
            } else {
                self.pasteViaClipboard(final, targetApp: targetApp, restoreClipboard: restoreClipboard, restoreDelayMs: restoreDelayMs)
            }
        }
    }

    private func pasteViaClipboard(
        _ text: String,
        targetApp: NSRunningApplication?,
        restoreClipboard: Bool,
        restoreDelayMs: Double
    ) {
        let pasteboard = NSPasteboard.general
        let savedEntries = restoreClipboard ? savePasteboard(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCmdV(targetApp: targetApp)

        if restoreClipboard {
            let delaySeconds = max(0.5, restoreDelayMs / 1000.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                self?.restorePasteboard(pasteboard, from: savedEntries)
            }
        }
    }

    private func postCmdV(targetApp: NSRunningApplication?) {
        if PermissionsHelper.shared.isAccessibilityGranted() {
            guard let source = CGEventSource(stateID: .hidSystemState) else {
                logger.error("Failed to create hidSystemState CGEventSource.")
                fallbackAppleScriptPaste()
                return
            }

            let cmdKeyCode: CGKeyCode = 0x37 // Left Command
            let vKeyCode: CGKeyCode = 0x09   // 'v'

            guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
                  let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
                  let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
                  let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
                logger.error("Failed to create CGEvent for Cmd+V.")
                fallbackAppleScriptPaste()
                return
            }

            cmdDown.flags = .maskCommand
            vDown.flags = .maskCommand
            vUp.flags = .maskCommand
            cmdUp.flags = []

            cmdDown.post(tap: .cghidEventTap)
            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
            cmdUp.post(tap: .cghidEventTap)
            logger.debug("Posted full Cmd+V key sequence via .cghidEventTap.")
        } else {
            // If Accessibility is not yet granted, CGEvent is dropped by macOS. Execute AppleScript fallback.
            logger.notice("Accessibility not granted to Orca Whisper. Executing AppleScript paste fallback.")
            fallbackAppleScriptPaste()
        }
    }

    private func fallbackAppleScriptPaste() {
        let script = "tell application \"System Events\" to keystroke \"v\" using command down"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                logger.error("AppleScript paste error: \(String(describing: err))")
            } else {
                logger.debug("AppleScript paste executed successfully.")
            }
        }
    }

    private func typeText(_ text: String, targetApp: NSRunningApplication?) {
        if PermissionsHelper.shared.isAccessibilityGranted() {
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }

            let utf16 = Array(text.utf16)
            let chunkSize = 20
            for start in stride(from: 0, to: utf16.count, by: chunkSize) {
                let end = min(start + chunkSize, utf16.count)
                var chunk = Array(utf16[start..<end])
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    continue
                }
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)

                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                usleep(4000) // 4 ms between chunks
            }
            logger.debug("Typed text directly using CGEvent unicode keystrokes.")
        } else {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to keystroke \"\(escaped)\""
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [SavedPasteboardEntry] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dataMap: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataMap[type] = data
                }
            }
            return SavedPasteboardEntry(types: item.types, dataMap: dataMap)
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, from entries: [SavedPasteboardEntry]) {
        guard !entries.isEmpty else { return }
        pasteboard.clearContents()
        for entry in entries {
            let item = NSPasteboardItem()
            for (type, data) in entry.dataMap {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
        logger.debug("Restored previous pasteboard contents.")
    }
}
