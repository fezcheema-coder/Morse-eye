import AppKit
import ScreenCaptureKit

enum Screenshot {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            openPrivacySettings("Privacy_ScreenCapture")
        }
    }

    static func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Capture the display under the mouse pointer as JPEG, with the longest edge
    /// at most `maxEdge` px. Morse Eye's own windows are left out of the picture.
    static func captureJPEG(maxEdge: Int = 1568, quality: Double = 0.8) async throws -> Data {
        guard hasPermission else {
            throw AppError("Morse Eye needs Screen Recording permission. Open Settings → General to grant it.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetID = displayUnderMouse() ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == targetID }) ?? content.displays.first else {
            throw AppError("No display found to capture.")
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = min(1.0, Double(maxEdge) / Double(max(display.width, display.height)))
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image)
            .representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw AppError("Couldn't encode the screenshot.")
        }
        return data
    }

    private static func displayUnderMouse() -> CGDirectDisplayID? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen?.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// A small blank image used by "Test connection".
    /// Drawn with Core Graphics in RGBA: a 24-bit RGB bitmap can't be drawn into
    /// on macOS, which is what made earlier versions crash here.
    static func blankJPEG() -> Data {
        let size = 64
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = ctx.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [:]) ?? Data()
    }
}
