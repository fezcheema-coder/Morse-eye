import AppKit
import IOKit

enum OutputDevice: String, Codable, CaseIterable, Identifiable {
    case capsLock, backlight, menuBar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .capsLock: "Caps Lock light"
        case .backlight: "Keyboard backlight"
        case .menuBar: "Menu bar icon"
        }
    }
    var detail: String {
        switch self {
        case .capsLock: "Works with any Mac keyboard. Caps Lock is really on while lit, so avoid typing during playback."
        case .backlight: "Built-in MacBook keyboards only. Uses a private macOS feature that a future update could change."
        case .menuBar: "Blinks the Morse Eye icon in the menu bar. Handy for testing."
        }
    }
}

@MainActor
protocol LEDOutput: AnyObject {
    func begin()
    func set(_ on: Bool)
    func end()
}

/// Caps Lock LED through IOKit. The HID lock-state functions are looked up at runtime
/// so the app builds regardless of which IOKit headers the SDK exposes to Swift.
@MainActor
final class CapsLockLED: LEDOutput {
    private typealias SetFn = @convention(c) (io_connect_t, Int32, Bool) -> kern_return_t
    private typealias GetFn = @convention(c) (io_connect_t, Int32, UnsafeMutablePointer<Bool>) -> kern_return_t

    private static let capsLockSelector: Int32 = 1   // kIOHIDCapsLockState
    private static let paramConnectType: UInt32 = 1  // kIOHIDParamConnectType

    private var connect: io_connect_t = 0
    private let setState: SetFn
    private let getState: GetFn
    private var original = false

    init() throws {
        guard let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let setSym = dlsym(lib, "IOHIDSetModifierLockState"),
              let getSym = dlsym(lib, "IOHIDGetModifierLockState") else {
            throw AppError("This Mac doesn't expose Caps Lock control.")
        }
        setState = unsafeBitCast(setSym, to: SetFn.self)
        getState = unsafeBitCast(getSym, to: GetFn.self)

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { throw AppError("Couldn't find the keyboard system service.") }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, Self.paramConnectType, &connect)
        guard result == KERN_SUCCESS else { throw AppError("Couldn't open the keyboard (error \(result)).") }
    }

    deinit { IOServiceClose(connect) }

    func begin() {
        var state = false
        _ = getState(connect, Self.capsLockSelector, &state)
        original = state
    }

    func set(_ on: Bool) { _ = setState(connect, Self.capsLockSelector, on) }

    func end() { set(original) }
}

/// Built-in keyboard backlight through the private CoreBrightness framework.
@MainActor
final class BacklightLED: LEDOutput {
    private let client: NSObject
    private let keyboard: UInt64
    private let onLevel: Float
    private var originalLevel: Float = 0.5
    private var originalAuto: Bool?

    init(level: Double) throws {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              bundle.load(),
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            throw AppError("Keyboard backlight control isn't available on this Mac.")
        }
        client = cls.init()
        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: idsSel),
              let ids = client.perform(idsSel)?.takeRetainedValue() as? [NSNumber],
              let first = ids.first else {
            throw AppError("No built-in keyboard backlight found.")
        }
        keyboard = first.uint64Value
        onLevel = Float(level)
    }

    private func call<T>(_ name: String, as type: T.Type) -> T? {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return nil }
        return unsafeBitCast(client.method(for: sel), to: type)
    }

    private typealias GetLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetLevel = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias SetLevelFast = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
    private typealias GetAuto = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias SetAuto = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Void

    func begin() {
        if let get = call("brightnessForKeyboard:", as: GetLevel.self) {
            originalLevel = get(client, NSSelectorFromString("brightnessForKeyboard:"), keyboard)
        }
        if let getAuto = call("isAutoBrightnessEnabledForKeyboard:", as: GetAuto.self),
           let setAuto = call("enableAutoBrightness:forKeyboard:", as: SetAuto.self) {
            originalAuto = getAuto(client, NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:"), keyboard)
            setAuto(client, NSSelectorFromString("enableAutoBrightness:forKeyboard:"), false, keyboard)
        }
    }

    private func setLevel(_ level: Float) {
        // fadeSpeed 0 switches instantly instead of the usual slow fade
        if let fast = call("setBrightness:fadeSpeed:commit:forKeyboard:", as: SetLevelFast.self) {
            _ = fast(client, NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:"), level, 0, true, keyboard)
        } else if let slow = call("setBrightness:forKeyboard:", as: SetLevel.self) {
            _ = slow(client, NSSelectorFromString("setBrightness:forKeyboard:"), level, keyboard)
        }
    }

    func set(_ on: Bool) { setLevel(on ? onLevel : 0) }

    func end() {
        setLevel(originalLevel)
        if let auto = originalAuto, let setAuto = call("enableAutoBrightness:forKeyboard:", as: SetAuto.self) {
            setAuto(client, NSSelectorFromString("enableAutoBrightness:forKeyboard:"), auto, keyboard)
        }
    }
}

/// Blinks the menu bar icon.
@MainActor
final class MenuBarLED: LEDOutput {
    private let setLit: @MainActor (Bool) -> Void
    init(setLit: @escaping @MainActor (Bool) -> Void) { self.setLit = setLit }
    func begin() {}
    func set(_ on: Bool) { setLit(on) }
    func end() { setLit(false) }
}
