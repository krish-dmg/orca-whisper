import Foundation
import CoreGraphics
import AppKit

enum ModifierKey: String, CaseIterable, Identifiable, Codable {
    case anyOption = "Option (Left or Right)"
    case leftOption = "Left Option"
    case rightOption = "Right Option"
    case anyFn = "Function (Fn / Globe - Any)"
    case leftFn = "Left Function (Fn / Globe)"
    case rightFn = "Right Function (Fn)"
    case anyCommand = "Command (Left or Right)"
    case leftCommand = "Left Command"
    case rightCommand = "Right Command"
    case anyControl = "Control (Left or Right)"
    case leftControl = "Left Control"
    case rightControl = "Right Control"
    case anyShift = "Shift (Left or Right)"
    case leftShift = "Left Shift"
    case rightShift = "Right Shift"
    case capsLock = "Caps Lock"

    var id: String { rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "Option (Left or Right)": self = .anyOption
        case "Left Option": self = .leftOption
        case "Right Option": self = .rightOption
        case "Function (Fn / Globe)", "Function (Fn / Globe - Any)": self = .anyFn
        case "Left Function (Fn / Globe)", "Left Function": self = .leftFn
        case "Right Function (Fn)", "Right Function": self = .rightFn
        case "Command (Left or Right)": self = .anyCommand
        case "Left Command": self = .leftCommand
        case "Right Command": self = .rightCommand
        case "Control (Left or Right)": self = .anyControl
        case "Left Control": self = .leftControl
        case "Right Control": self = .rightControl
        case "Shift (Left or Right)": self = .anyShift
        case "Left Shift": self = .leftShift
        case "Right Shift": self = .rightShift
        case "Caps Lock": self = .capsLock
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .anyOption: return "Option (Left or Right)"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .anyFn: return "Function (Fn / Globe - Any)"
        case .leftFn: return "Left Function (Fn / Globe)"
        case .rightFn: return "Right Function (Fn)"
        case .anyCommand: return "Command (Left or Right)"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        case .anyControl: return "Control (Left or Right)"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .anyShift: return "Shift (Left or Right)"
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .capsLock: return "Caps Lock"
        }
    }

    func matchesCGEvent(keyCode: UInt16, flags: CGEventFlags) -> (isTargetKey: Bool, isPressed: Bool) {
        switch self {
        case .anyOption:
            let isTarget = (keyCode == 58 || keyCode == 61)
            let isPressed = flags.contains(.maskAlternate)
            return (isTarget, isPressed)
        case .leftOption:
            return (keyCode == 58, flags.contains(.maskAlternate))
        case .rightOption:
            return (keyCode == 61, flags.contains(.maskAlternate))
        case .anyFn, .leftFn, .rightFn:
            let isTarget = (keyCode == 63 || flags.contains(.maskSecondaryFn))
            let isPressed = flags.contains(.maskSecondaryFn)
            return (isTarget, isPressed)
        case .anyCommand:
            let isTarget = (keyCode == 54 || keyCode == 55)
            let isPressed = flags.contains(.maskCommand)
            return (isTarget, isPressed)
        case .leftCommand:
            return (keyCode == 55, flags.contains(.maskCommand))
        case .rightCommand:
            return (keyCode == 54, flags.contains(.maskCommand))
        case .anyControl:
            let isTarget = (keyCode == 59 || keyCode == 62)
            let isPressed = flags.contains(.maskControl)
            return (isTarget, isPressed)
        case .leftControl:
            return (keyCode == 59, flags.contains(.maskControl))
        case .rightControl:
            return (keyCode == 62, flags.contains(.maskControl))
        case .anyShift:
            let isTarget = (keyCode == 56 || keyCode == 60)
            let isPressed = flags.contains(.maskShift)
            return (isTarget, isPressed)
        case .leftShift:
            return (keyCode == 56, flags.contains(.maskShift))
        case .rightShift:
            return (keyCode == 60, flags.contains(.maskShift))
        case .capsLock:
            return (keyCode == 57, flags.contains(.maskAlphaShift))
        }
    }

    func matchesNSEvent(_ event: NSEvent) -> (isTargetKey: Bool, isPressed: Bool) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags
        switch self {
        case .anyOption:
            let isTarget = (keyCode == 58 || keyCode == 61)
            let isPressed = flags.contains(.option)
            return (isTarget, isPressed)
        case .leftOption:
            return (keyCode == 58, flags.contains(.option))
        case .rightOption:
            return (keyCode == 61, flags.contains(.option))
        case .anyFn, .leftFn, .rightFn:
            let isTarget = (keyCode == 63 || flags.contains(.function))
            let isPressed = flags.contains(.function)
            return (isTarget, isPressed)
        case .anyCommand:
            let isTarget = (keyCode == 54 || keyCode == 55)
            let isPressed = flags.contains(.command)
            return (isTarget, isPressed)
        case .leftCommand:
            return (keyCode == 55, flags.contains(.command))
        case .rightCommand:
            return (keyCode == 54, flags.contains(.command))
        case .anyControl:
            let isTarget = (keyCode == 59 || keyCode == 62)
            let isPressed = flags.contains(.control)
            return (isTarget, isPressed)
        case .leftControl:
            return (keyCode == 59, flags.contains(.control))
        case .rightControl:
            return (keyCode == 62, flags.contains(.control))
        case .anyShift:
            let isTarget = (keyCode == 56 || keyCode == 60)
            let isPressed = flags.contains(.shift)
            return (isTarget, isPressed)
        case .leftShift:
            return (keyCode == 56, flags.contains(.shift))
        case .rightShift:
            return (keyCode == 60, flags.contains(.shift))
        case .capsLock:
            return (keyCode == 57, flags.contains(.capsLock))
        }
    }
}

enum HotkeyTrigger: Codable, Equatable {
    case singleModifier(ModifierKey)
    case keyCombo(modifiers: UInt64, keyCode: UInt16, displayString: String)

    var displayName: String {
        switch self {
        case .singleModifier(let mod):
            return mod.rawValue
        case .keyCombo(_, _, let display):
            return display
        }
    }
}
