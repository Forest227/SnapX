import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum HotKeyRegistrationOutcome {
    case registered
    case requiresAccessibilityPermission
    case failed(OSStatus)
}

struct HotKeyModifiers: OptionSet {
    let rawValue: UInt32

    static let command = HotKeyModifiers(rawValue: UInt32(cmdKey))
    static let option = HotKeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotKeyModifiers(rawValue: UInt32(controlKey))
    static let shift = HotKeyModifiers(rawValue: UInt32(shiftKey))

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

final class GlobalHotKeyMonitor {
    private static let signature = OSType(0x53424F41)

    private let keyCode: UInt32
    private let modifiers: HotKeyModifiers
    private let handler: @Sendable () -> Void
    private let hotKeyID: EventHotKeyID

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventTapInterceptor: EventTapHotKeyInterceptor?

    init(identifier: UInt32, keyCode: UInt32, modifiers: HotKeyModifiers, handler: @escaping @Sendable () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        self.hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: identifier
        )
    }

    @discardableResult
    func register() -> HotKeyRegistrationOutcome {
        guard hotKeyRef == nil else { return .registered }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }

                let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                var pressedHotKeyID = EventHotKeyID()

                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard status == noErr,
                      pressedHotKeyID.signature == monitor.hotKeyID.signature,
                      pressedHotKeyID.id == monitor.hotKeyID.id else {
                    return noErr
                }

                monitor.handler()

                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else { return .failed(handlerStatus) }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            return .failed(registerStatus)
        }

        guard modifiers.contains(.command) else {
            return .registered
        }

        let interceptor = EventTapHotKeyInterceptor(
            keyCode: keyCode,
            modifiers: modifiers,
            handler: handler
        )

        switch interceptor.start() {
        case .started:
            eventTapInterceptor = interceptor
            return .registered

        case .requiresAccessibilityPermission:
            return .requiresAccessibilityPermission

        case let .failed(status):
            unregister()
            return .failed(status)
        }
    }

    func unregister() {
        eventTapInterceptor?.stop()
        eventTapInterceptor = nil

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}

private enum EventTapRegistrationOutcome {
    case started
    case requiresAccessibilityPermission
    case failed(OSStatus)
}

private final class EventTapHotKeyInterceptor {
    private let keyCode: UInt32
    private let modifiers: HotKeyModifiers
    private let handler: @Sendable () -> Void
    private let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(keyCode: UInt32, modifiers: HotKeyModifiers, handler: @escaping @Sendable () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    func start() -> EventTapRegistrationOutcome {
        guard eventTap == nil else { return .started }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let interceptor = Unmanaged<EventTapHotKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            return interceptor.handleEvent(type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return AXIsProcessTrusted() ? .failed(OSStatus(-1)) : .requiresAccessibilityPermission
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource

        return .started
    }

    func stop() {
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let pressedKeyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        let normalizedFlags = event.flags.intersection(relevantFlags)

        guard !isAutoRepeat,
              pressedKeyCode == keyCode,
              normalizedFlags == modifiers.cgEventFlags else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [handler] in
            handler()
        }
        return nil
    }
}
