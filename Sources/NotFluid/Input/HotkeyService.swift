import Foundation
import AppKit
import Carbon

/// Global push-to-talk with presets (Right ⌥, Right ⌘, F13, ⌥Space).
final class HotkeyService {
    var onToggle: ((Bool) -> Void)?

    static let syntheticEventMarker: Int64 = 0x4E30464C
    static let rightOptionKeyCode: UInt16 = 61
    static let rightCommandKeyCode: UInt16 = 54
    static let f13KeyCode: UInt16 = 105
    static let spaceKeyCode: UInt16 = 49

    private static let leftOptionDeviceMask: UInt64 = 0x20
    private static let rightOptionDeviceMask: UInt64 = 0x40
    private static let leftCommandDeviceMask: UInt64 = 0x08
    private static let rightCommandDeviceMask: UInt64 = 0x10

    private var isDown = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var mode: HotkeyMode = .rightOption
    private var deviceBitsObserved = false
    private var lastToggleUptime: TimeInterval = 0
    private let debounce: TimeInterval = 0.05

    enum HotkeyMode: Equatable {
        case rightOption
        case rightCommand
        case keyCombo(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)
    }

    deinit { unregister() }

    func register(preset: HotkeyPreset) {
        switch preset {
        case .rightOption:
            register(mode: .rightOption)
        case .rightCommand:
            register(mode: .rightCommand)
        case .fnF13:
            register(mode: .keyCombo(keyCode: Self.f13KeyCode, modifiers: []))
        case .optionSpace:
            register(mode: .keyCombo(keyCode: Self.spaceKeyCode, modifiers: .option))
        }
    }

    func registerRightOption() { register(preset: .rightOption) }

    func register(mode: HotkeyMode) {
        unregister()
        self.mode = mode
        deviceBitsObserved = false
        isDown = false

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
            self?.handle(e)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            self?.handle(e)
            return e
        }
    }

    func unregister() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        isDown = false
    }

    private func handle(_ event: NSEvent) {
        if let cg = event.cgEvent,
           cg.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return
        }
        switch mode {
        case .rightOption:
            handleModifierKey(event, keyCode: Self.rightOptionKeyCode, deviceMask: Self.rightOptionDeviceMask, leftMask: Self.leftOptionDeviceMask, flag: .option)
        case .rightCommand:
            handleModifierKey(event, keyCode: Self.rightCommandKeyCode, deviceMask: Self.rightCommandDeviceMask, leftMask: Self.leftCommandDeviceMask, flag: .command)
        case .keyCombo(let keyCode, let modifiers):
            handleKeyCombo(event, keyCode: keyCode, modifiers: modifiers)
        }
    }

    private func handleModifierKey(
        _ event: NSEvent,
        keyCode: UInt16,
        deviceMask: UInt64,
        leftMask: UInt64,
        flag: NSEvent.ModifierFlags
    ) {
        guard event.type == .flagsChanged else { return }
        guard event.keyCode == keyCode else { return }

        let pressed: Bool = {
            if let raw = event.cgEvent?.flags.rawValue {
                let left = (raw & leftMask) != 0
                let right = (raw & deviceMask) != 0
                if left || right { deviceBitsObserved = true }
                if deviceBitsObserved { return right }
            }
            return event.modifierFlags.contains(flag)
        }()

        emit(pressed)
    }

    private func handleKeyCombo(
        _ event: NSEvent,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) {
        if event.type == .flagsChanged { return }
        guard event.keyCode == keyCode else { return }

        let wanted = modifiers.intersection([.command, .option, .control, .shift])
        let active = event.modifierFlags.intersection([.command, .option, .control, .shift])

        guard active == wanted else {
            if isDown && event.type == .keyUp { emit(false) }
            return
        }

        if event.type == .keyDown && !event.isARepeat {
            emit(true)
        } else if event.type == .keyUp {
            emit(false)
        }
    }

    private func emit(_ pressed: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if pressed && !isDown {
            guard now - lastToggleUptime >= debounce else { return }
            isDown = true
            lastToggleUptime = now
            DispatchQueue.main.async { [weak self] in self?.onToggle?(true) }
        } else if !pressed && isDown {
            guard now - lastToggleUptime >= debounce else { return }
            isDown = false
            lastToggleUptime = now
            DispatchQueue.main.async { [weak self] in self?.onToggle?(false) }
        }
    }
}
