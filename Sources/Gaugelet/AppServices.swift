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
    static func iconState(for state: UsageState, pinnedID: String? = nil) -> GaugeletMenuBarIconState {
        switch state {
        case .loading:
            return GaugeletMenuBarIconState(mode: .loading, percent: nil)
        case .unavailable:
            return GaugeletMenuBarIconState(mode: .unavailable, percent: nil)
        case .live(let snapshot):
            return iconState(for: snapshot, fallback: .live, pinnedID: pinnedID)
        case .stale(let snapshot, _, _):
            return iconState(for: snapshot, fallback: .stale, pinnedID: pinnedID)
        case .demo(let snapshot):
            return iconState(for: snapshot, fallback: .demo, pinnedID: pinnedID)
        }
    }

    private static func iconState(
        for snapshot: UsageSnapshot,
        fallback: GaugeletMenuBarIconMode,
        pinnedID: String?
    ) -> GaugeletMenuBarIconState {
        guard snapshot.isSignedIn else {
            return GaugeletMenuBarIconState(mode: .signedOut, percent: nil)
        }
        guard let closestLimit = pinnedID.map({ snapshot.menuBarLimit(pinnedID: $0) }) ?? snapshot.closestLimit else {
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
    case usage = "https://chatgpt.com/codex/settings/usage"
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
    private static let menuBarIconSize = NSSize(width: 16, height: 16)
    private static let menuBarGlyph: NSImage = {
        if let url = Bundle.main.url(forResource: "GaugeletMenuBar", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = menuBarIconSize
            image.isTemplate = true
            return image
        }

        return renderMenuBarGlyph()
    }()

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
        for _: GaugeletIconStyle,
        mode _: GaugeletMenuBarIconMode,
        percent _: Int? = nil,
        isDark _: Bool
    ) -> NSImage {
        menuBarGlyph
    }

    private static func renderMenuBarGlyph() -> NSImage {
        let renderedImage = NSImage(size: menuBarIconSize)
        renderedImage.lockFocus()
        defer { renderedImage.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            renderedImage.isTemplate = true
            return renderedImage
        }

        context.clear(CGRect(origin: .zero, size: menuBarIconSize))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let arc = CGMutablePath()
        arc.addArc(
            center: CGPoint(x: 8, y: 6),
            radius: 5.5,
            startAngle: 0,
            endAngle: .pi,
            clockwise: false
        )
        context.addPath(arc)
        context.strokePath()

        context.move(to: CGPoint(x: 8, y: 6))
        context.addLine(to: CGPoint(x: 8.815, y: 9.66))
        context.strokePath()

        context.fillEllipse(in: CGRect(x: 6.8, y: 4.8, width: 2.4, height: 2.4))
        renderedImage.isTemplate = true
        return renderedImage
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
