import AppKit
import Foundation
import ServiceManagement
import UserNotifications

enum GaugeletMenuBarIconMode: Hashable {
    case loading
    case unavailable
    case live
    case stale
    case demo
    case blocked
    case signedOut
}

struct GaugeletMenuBarIconState: Equatable {
    let mode: GaugeletMenuBarIconMode
    let percent: Int?
}

enum GaugeletMenuBarPresentation {
    static func iconState(for state: UsageState) -> GaugeletMenuBarIconState {
        switch state {
        case .loading:
            return GaugeletMenuBarIconState(mode: .loading, percent: nil)
        case .unavailable:
            return GaugeletMenuBarIconState(mode: .unavailable, percent: nil)
        case .live(let snapshot):
            return iconState(for: snapshot, fallback: .live)
        case .stale(let snapshot, _, _):
            return iconState(for: snapshot, fallback: .stale)
        case .demo(let snapshot):
            return iconState(for: snapshot, fallback: .demo)
        }
    }

    private static func iconState(
        for snapshot: UsageSnapshot,
        fallback: GaugeletMenuBarIconMode
    ) -> GaugeletMenuBarIconState {
        guard snapshot.isSignedIn else {
            return GaugeletMenuBarIconState(mode: .signedOut, percent: nil)
        }
        guard let closestLimit = snapshot.closestLimit else {
            return GaugeletMenuBarIconState(mode: fallback, percent: nil)
        }

        let percent = closestLimit.clampedRemainingPercent
        if closestLimit.blockedReason != nil {
            return GaugeletMenuBarIconState(mode: .blocked, percent: percent)
        }
        return GaugeletMenuBarIconState(mode: fallback, percent: percent)
    }
}

enum GaugeletLink: String, CaseIterable, Sendable {
    case chatGPT = "https://chatgpt.com"
    case releases = "https://github.com/lammworks/Gaugelet/releases"
    case buyMeACoffee = "https://www.paypal.com/donate/?hosted_button_id=Z4QV6SJVXSCH4"
    case privacy = "https://github.com/lammworks/Gaugelet/blob/main/PRIVACY.md"
    case source = "https://github.com/lammworks/Gaugelet"
    case codexSetup = "https://learn.chatgpt.com/docs/codex/cli"

    var url: URL {
        // These are compile-time product constants, not user-provided URLs.
        URL(string: rawValue)!
    }
}

enum GaugeletSparkleConfiguration {
    static let publicKeyPlaceholder =
        "RELEASE_BLOCKED_REPLACE_WITH_SPARKLE_ED25519_PUBLIC_KEY"

    static func isReleaseConfigured(infoDictionary: [String: Any]?) -> Bool {
        guard
            let publicKey = infoDictionary?["SUPublicEDKey"] as? String,
            publicKey != publicKeyPlaceholder,
            let decodedKey = Data(base64Encoded: publicKey),
            decodedKey.count == 32
        else {
            return false
        }

        return true
    }
}

enum GaugeletBuildInfo {
    static var versionAndBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (.some(version), .some(build)) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (.some(version), _) where !version.isEmpty:
            return "Version \(version)"
        case let (_, .some(build)) where !build.isEmpty:
            return "Build \(build)"
        default:
            return "Development build"
        }
    }
}

@MainActor
final class GaugeletNotificationManager {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func deliver(_ alert: GaugeletUsageAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: alert.identifier,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            // Notification delivery is optional and must never affect usage refreshes.
        }
    }
}

@MainActor
enum GaugeletSystemIcon {
    private static let legacyFinderIconFileName = "Icon\r"

    static func hasLegacyFinderOverride(
        at bundleURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let legacyIconURL = bundleURL.appendingPathComponent(
            legacyFinderIconFileName,
            isDirectory: false
        )
        return fileManager.fileExists(atPath: legacyIconURL.path)
    }

    @discardableResult
    static func clearLegacyFinderOverride(
        at bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        clearIcon: (String) -> Bool = { path in
            NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
        },
        noteFileSystemChanged: (String) -> Void = { path in
            NSWorkspace.shared.noteFileSystemChanged(path)
        }
    ) -> Bool {
        guard hasLegacyFinderOverride(at: bundleURL, fileManager: fileManager) else {
            return false
        }
        guard clearIcon(bundleURL.path) else {
            return false
        }

        noteFileSystemChanged(bundleURL.path)
        return true
    }
}

enum GaugeletAppIcon {
    private static let menuBarCanvasSize: CGFloat = 32
    private static var menuBarImageCache = [MenuBarIconCacheKey: NSImage]()

    static func image(for style: GaugeletIconStyle) -> NSImage? {
        let resourceNames = [
            "GaugeletIcon-\(style.resourceName)-1024",
            "GaugeletIcon-\(style.resourceName)-256"
        ]
        for resource in resourceNames {
            if let url = Bundle.main.url(forResource: resource, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        if style == .core,
           let url = Bundle.main.url(forResource: "Gaugelet", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return nil
    }

    static func menuBarImage(
        for style: GaugeletIconStyle,
        mode: GaugeletMenuBarIconMode,
        percent: Int? = nil,
        isDark: Bool
    ) -> NSImage {
        let clamped = percent.map { min(max($0, 0), 100) } ?? 0
        let key = MenuBarIconCacheKey(
            style: style,
            mode: mode,
            percent: clamped,
            isDark: isDark
        )

        if let cached = menuBarImageCache[key] {
            return cached
        }

        let image = renderMenuBarIcon(
            for: style,
            mode: mode,
            percent: clamped,
            isDark: isDark
        )
        menuBarImageCache[key] = image
        return image
    }

    static func invalidateMenuBarIconCache() {
        menuBarImageCache.removeAll()
    }

    private static func renderMenuBarIcon(
        for style: GaugeletIconStyle,
        mode: GaugeletMenuBarIconMode,
        percent: Int,
        isDark: Bool
    ) -> NSImage {
        let renderedImage = NSImage(
            size: NSSize(width: menuBarCanvasSize, height: menuBarCanvasSize)
        )
        renderedImage.lockFocus()
        defer { renderedImage.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image(for: style) ?? renderedImage
        }

        context.clear(CGRect(origin: .zero, size: CGSize(width: menuBarCanvasSize, height: menuBarCanvasSize))
)

        let accent = modeColor(for: style, isDark: isDark, mode: mode)
        let neutral = isDark ? NSColor.white.withAlphaComponent(0.36) : NSColor.black.withAlphaComponent(0.35)
        let backgroundColor = isDark
            ? NSColor(calibratedWhite: 0.21, alpha: 1.0)
            : NSColor(calibratedWhite: 0.95, alpha: 1.0)
        let trackColor = isDark
            ? NSColor(white: 1, alpha: 0.17)
            : NSColor(white: 0, alpha: 0.18)
        let textColor = isDark ? NSColor(white: 1, alpha: 0.9) : NSColor(white: 0.14, alpha: 0.85)

        let cardInset: CGFloat = 2.5
        let cardRect = CGRect(
            x: cardInset,
            y: cardInset,
            width: menuBarCanvasSize - 2 * cardInset,
            height: menuBarCanvasSize - 2 * cardInset
        )
        let cardRadius = cardRect.height * 0.24
        let cardPath = NSBezierPath(
            roundedRect: cardRect,
            xRadius: cardRadius,
            yRadius: cardRadius
        )
        backgroundColor.setFill()
        cardPath.fill()

        cardColor(for: accent, alpha: 0.22).setFill()
        NSBezierPath(
            roundedRect: cardRect.insetBy(dx: 1.6, dy: 1.6),
            xRadius: cardRadius - 1.0,
            yRadius: cardRadius - 1.0
        ).fill()

        let center = CGPoint(
            x: menuBarCanvasSize / 2,
            y: menuBarCanvasSize / 2
        )
        let radius = cardRect.width * 0.34
        let lineWidth = cardRect.width * 0.12

        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(trackColor.cgColor)

        let trackPath = CGMutablePath()
        trackPath.addArc(
            center: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: false
        )
        context.addPath(trackPath)

        context.strokePath()

        if mode == .unavailable || mode == .signedOut {
            context.setStrokeColor(neutral.withAlphaComponent(0.72).cgColor)
        } else {
            context.setStrokeColor(accent.cgColor)
        }
        context.setLineWidth(lineWidth * 1.02)
        let fillProgress = CGFloat(percent) / 100.0
        let ringPath = CGMutablePath()
        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + (2 * CGFloat.pi * fillProgress)
        ringPath.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        context.addPath(ringPath)
        if mode == .loading {
            context.strokePath()
        } else {
            context.strokePath()
        }

        if mode == .loading || mode == .unavailable || mode == .signedOut {
            let statusDot = NSBezierPath(ovalIn: CGRect(
                x: center.x - 1.9,
                y: center.y - 1.9,
                width: 3.8,
                height: 3.8
            ))
            (mode == .loading ? textColor : neutral).setFill()
            statusDot.fill()
        }

        if mode == .blocked || mode == .stale {
            let warning = NSBezierPath()
            warning.lineWidth = 1.6
            warning.move(to: CGPoint(
                x: cardInset + 6,
                y: cardRect.maxY - 6.2
            ))
            warning.line(to: CGPoint(
                x: cardRect.maxX - 6,
                y: cardInset + 6.2
            ))
            warning.lineCapStyle = .round
            accent.withAlphaComponent(0.75).setStroke()
            warning.stroke()
        }

        if mode == .stale {
            let oldText = "s"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: textColor
            ]
            let attributed = NSAttributedString(string: oldText, attributes: attrs)
            let textSize = attributed.size()
            attributed.draw(
                at: CGPoint(
                    x: center.x - textSize.width / 2,
                    y: center.y - textSize.height / 2 - 1
                )
            )
        }

        if mode == .demo {
            let demoText = "D"
            let demoAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: accent.withAlphaComponent(0.9)
            ]
            let attributedDemo = NSAttributedString(string: demoText, attributes: demoAttrs)
            let size = attributedDemo.size()
            attributedDemo.draw(
                at: CGPoint(
                    x: center.x - size.width / 2,
                    y: center.y - size.height / 2 - 1
                )
            )
        }

        if mode != .loading && mode != .unavailable && mode != .signedOut {
            let percentText = "\(percent)"
            let percentAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8.0, weight: .bold),
                .foregroundColor: textColor
            ]
            let attributedPercent = NSAttributedString(
                string: percentText,
                attributes: percentAttrs
            )
            let size = attributedPercent.size()
            attributedPercent.draw(
                at: CGPoint(
                    x: center.x - size.width / 2,
                    y: 3.4
                )
            )
        }

        return renderedImage
    }

    private static func modeColor(
        for style: GaugeletIconStyle,
        isDark: Bool,
        mode: GaugeletMenuBarIconMode
    ) -> NSColor {
        switch mode {
        case .blocked, .loading:
            return NSColor(red: 0.82, green: 0.22, blue: 0.21, alpha: 1)
        case .unavailable, .signedOut:
            return isDark
                ? NSColor(white: 0.70, alpha: 1)
                : NSColor(white: 0.38, alpha: 1)
        case .demo:
            return styleColor(for: style, dark: isDark)
        case .live, .stale:
            return styleColor(for: style, dark: isDark)
        }
    }

    private static func styleColor(for style: GaugeletIconStyle, dark: Bool) -> NSColor {
        let palette = style.accentPalette
        let rgb = dark ? palette.darkRGB : palette.lightRGB
        return NSColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func cardColor(for accent: NSColor, alpha: CGFloat) -> NSColor {
        accent.withAlphaComponent(alpha)
    }

    private struct MenuBarIconCacheKey: Hashable {
        let style: GaugeletIconStyle
        let mode: GaugeletMenuBarIconMode
        let percent: Int
        let isDark: Bool
    }
}

enum LaunchAtLoginServiceStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

struct LaunchAtLoginInstallContext: Equatable, Sendable {
    let bundleURL: URL
    let isVolumeReadOnly: Bool
    let isTranslocated: Bool

    static func current(bundleURL: URL = Bundle.main.bundleURL) -> Self {
        let standardizedPath = bundleURL.standardizedFileURL.path
        let resolvedPath = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let isTranslocated = standardizedPath.contains("/AppTranslocation/")
            || resolvedPath.contains("/AppTranslocation/")
        let resourceValues = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])

        return Self(
            bundleURL: bundleURL,
            isVolumeReadOnly: resourceValues?.volumeIsReadOnly ?? false,
            isTranslocated: isTranslocated
        )
    }
}

enum LaunchAtLoginInstallEligibility: Equatable, Sendable {
    static let moveToApplicationsMessage = "Move Gaugelet to Applications first."

    case eligible
    case ineligible(message: String)

    static func evaluate(_ context: LaunchAtLoginInstallContext) -> Self {
        guard !context.isVolumeReadOnly, !context.isTranslocated else {
            return .ineligible(message: moveToApplicationsMessage)
        }

        let bundleComponents = context.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents
        let applicationsComponents = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        ).pathComponents

        guard
            bundleComponents.count > applicationsComponents.count,
            bundleComponents.starts(with: applicationsComponents)
        else {
            return .ineligible(message: moveToApplicationsMessage)
        }

        return .eligible
    }

    var isEligible: Bool {
        self == .eligible
    }
}

enum LaunchAtLoginStatus: Equatable, Sendable {
    case off
    case enabled
    case requiresApproval
    case unavailable(message: String)
    case registrationError(message: String)

    var title: String {
        switch self {
        case .off: "Off"
        case .enabled: "On"
        case .requiresApproval: "Needs approval"
        case .unavailable: "Unavailable"
        case .registrationError: "Error"
        }
    }

    var detail: String? {
        switch self {
        case .off, .enabled:
            nil
        case .requiresApproval:
            "Gaugelet is registered, but macOS requires your approval in Login Items."
        case .unavailable(let message), .registrationError(let message):
            message
        }
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var isEnabled: Bool {
        self == .enabled
    }

    var needsSystemSettings: Bool {
        switch self {
        case .requiresApproval, .registrationError:
            true
        case .off, .enabled, .unavailable:
            false
        }
    }
}

enum LaunchAtLoginStateResolver {
    static func status(
        serviceStatus: LaunchAtLoginServiceStatus,
        eligibility: LaunchAtLoginInstallEligibility
    ) -> LaunchAtLoginStatus {
        if case .ineligible(let message) = eligibility {
            return .unavailable(message: message)
        }

        switch serviceStatus {
        case .notRegistered:
            return .off
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable(
                message: "Launch at Login is unavailable for this copy of Gaugelet."
            )
        }
    }
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginServiceStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let requestedDefaultsKey = "launchAtLoginRequested"

    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var isRequested: Bool

    private let service: any LaunchAtLoginServicing
    private let defaults: UserDefaults
    private let installContext: () -> LaunchAtLoginInstallContext
    private var eligibility: LaunchAtLoginInstallEligibility

    init(
        service: (any LaunchAtLoginServicing)? = nil,
        defaults: UserDefaults = .standard,
        installContext: @escaping () -> LaunchAtLoginInstallContext = {
            LaunchAtLoginInstallContext.current()
        }
    ) {
        let resolvedService = service ?? MainAppLaunchAtLoginService()
        self.service = resolvedService
        self.defaults = defaults
        self.installContext = installContext
        eligibility = LaunchAtLoginInstallEligibility.evaluate(installContext())

        let requested: Bool
        if defaults.object(forKey: Self.requestedDefaultsKey) == nil {
            requested = resolvedService.status == .enabled
                || resolvedService.status == .requiresApproval
            defaults.set(requested, forKey: Self.requestedDefaultsKey)
        } else {
            requested = defaults.bool(forKey: Self.requestedDefaultsKey)
        }
        isRequested = requested

        status = LaunchAtLoginStateResolver.status(
            serviceStatus: resolvedService.status,
            eligibility: eligibility
        )
        reconcileIntent()
    }

    var canChangeRequest: Bool {
        !status.isUnavailable
    }

    func refresh() {
        eligibility = LaunchAtLoginInstallEligibility.evaluate(installContext())
        reconcileIntent()
    }

    func setRequested(_ requested: Bool) {
        guard eligibility.isEligible else {
            status = LaunchAtLoginStateResolver.status(
                serviceStatus: service.status,
                eligibility: eligibility
            )
            return
        }

        isRequested = requested
        defaults.set(requested, forKey: Self.requestedDefaultsKey)
        reconcileIntent()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    private func reconcileIntent() {
        guard eligibility.isEligible else {
            status = LaunchAtLoginStateResolver.status(
                serviceStatus: service.status,
                eligibility: eligibility
            )
            return
        }

        do {
            let serviceStatus = service.status
            if isRequested && serviceStatus == .notRegistered {
                try service.register()
            } else if !isRequested && (
                serviceStatus == .enabled || serviceStatus == .requiresApproval
            ) {
                try service.unregister()
            }

            status = LaunchAtLoginStateResolver.status(
                serviceStatus: service.status,
                eligibility: eligibility
            )
        } catch {
            let action = isRequested ? "enable" : "disable"
            status = .registrationError(
                message: "Couldn’t \(action) Launch at Login: \(error.localizedDescription)"
            )
        }
    }
}
