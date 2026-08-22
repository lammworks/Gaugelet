import Foundation
import XCTest
@testable import Gaugelet

final class GaugeletReleaseConfigurationTests: XCTestCase {
    func testInfoPlistConfiguresVersionAndAuthenticatedSparkleDefaults() throws {
        let info = try loadPackagingInfoPlist()

        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "1.0.1")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "2")
        XCTAssertEqual(
            info["SUFeedURL"] as? String,
            "https://github.com/lammworks/Gaugelet/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            info["SUPublicEDKey"] as? String,
            "utJwIhvTYcNaYqRRxpJmxgmIoK3kCsrWJnCFWFIkxaY="
        )
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86_400)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertNil(
            info["SUEnableAutomaticChecks"],
            "Omitting this key lets Sparkle ask once before enabling scheduled checks."
        )
        XCTAssertTrue(GaugeletSparkleConfiguration.isReleaseConfigured(infoDictionary: info))
    }

    func testSparkleStartsOnlyWithA32ByteBase64PublicKey() {
        var info: [String: Any] = [
            "SUPublicEDKey": GaugeletSparkleConfiguration.publicKeyPlaceholder
        ]
        XCTAssertFalse(GaugeletSparkleConfiguration.isReleaseConfigured(infoDictionary: info))

        info["SUPublicEDKey"] = "not-base64"
        XCTAssertFalse(GaugeletSparkleConfiguration.isReleaseConfigured(infoDictionary: info))

        info["SUPublicEDKey"] = Data(repeating: 0xAB, count: 32).base64EncodedString()
        XCTAssertTrue(GaugeletSparkleConfiguration.isReleaseConfigured(infoDictionary: info))
    }

    func testPublicLinksUseApprovedDestinations() {
        XCTAssertEqual(
            GaugeletLink.releases.url.absoluteString,
            "https://github.com/lammworks/Gaugelet/releases"
        )
        XCTAssertEqual(
            GaugeletLink.buyMeACoffee.url.absoluteString,
            "https://www.paypal.com/donate/?hosted_button_id=Z4QV6SJVXSCH4"
        )
        XCTAssertEqual(
            GaugeletLink.privacy.url.absoluteString,
            "https://github.com/lammworks/Gaugelet/blob/main/PRIVACY.md"
        )
        XCTAssertEqual(
            GaugeletLink.source.url.absoluteString,
            "https://github.com/lammworks/Gaugelet"
        )
    }

    private func loadPackagingInfoPlist() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repositoryRoot.appendingPathComponent("Packaging/Info.plist")
        let data = try Data(contentsOf: infoURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
    }
}

final class LaunchAtLoginModelTests: XCTestCase {
    func testInstallEligibilityRequiresWritableNonTranslocatedApplicationsCopy() {
        XCTAssertEqual(
            LaunchAtLoginInstallEligibility.evaluate(context(path: "/Applications/Gaugelet.app")),
            .eligible
        )
        XCTAssertEqual(
            LaunchAtLoginInstallEligibility.evaluate(
                context(path: "/Applications/Utilities/Gaugelet.app")
            ),
            .eligible
        )

        let expected = LaunchAtLoginInstallEligibility.ineligible(
            message: "Move Gaugelet to Applications first."
        )
        XCTAssertEqual(
            LaunchAtLoginInstallEligibility.evaluate(
                context(path: "/Volumes/Gaugelet/Gaugelet.app", isVolumeReadOnly: true)
            ),
            expected
        )
        XCTAssertEqual(
            LaunchAtLoginInstallEligibility.evaluate(
                context(
                    path: "/private/var/folders/AppTranslocation/Gaugelet.app",
                    isTranslocated: true
                )
            ),
            expected
        )
        XCTAssertEqual(
            LaunchAtLoginInstallEligibility.evaluate(
                context(path: "/private/tmp/Gaugelet.app")
            ),
            expected
        )
    }

    func testStateResolverDistinguishesEveryServiceState() {
        XCTAssertEqual(
            LaunchAtLoginStateResolver.status(
                serviceStatus: .notRegistered,
                eligibility: .eligible
            ),
            .off
        )
        XCTAssertEqual(
            LaunchAtLoginStateResolver.status(serviceStatus: .enabled, eligibility: .eligible),
            .enabled
        )
        XCTAssertEqual(
            LaunchAtLoginStateResolver.status(
                serviceStatus: .requiresApproval,
                eligibility: .eligible
            ),
            .requiresApproval
        )
        XCTAssertEqual(
            LaunchAtLoginStateResolver.status(serviceStatus: .notFound, eligibility: .eligible),
            .unavailable(message: "Launch at Login is unavailable for this copy of Gaugelet.")
        )
        XCTAssertEqual(
            LaunchAtLoginStateResolver.status(
                serviceStatus: .enabled,
                eligibility: .ineligible(
                    message: LaunchAtLoginInstallEligibility.moveToApplicationsMessage
                )
            ),
            .unavailable(message: "Move Gaugelet to Applications first.")
        )
    }

    @MainActor
    func testExistingRegistrationMigratesToPersistedIntent() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLaunchAtLoginService(status: .enabled)

        let controller = LaunchAtLoginController(
            service: service,
            defaults: defaults,
            installContext: eligibleContext
        )

        XCTAssertTrue(controller.isRequested)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginController.requestedDefaultsKey))
        XCTAssertEqual(service.registerCallCount, 0)
    }

    @MainActor
    func testPersistedIntentReRegistersAfterAppReplacement() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: LaunchAtLoginController.requestedDefaultsKey)
        let service = FakeLaunchAtLoginService(status: .notRegistered)

        let controller = LaunchAtLoginController(
            service: service,
            defaults: defaults,
            installContext: eligibleContext
        )

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.status, .enabled)

        service.status = .notRegistered
        controller.refresh()

        XCTAssertEqual(service.registerCallCount, 2)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(controller.isRequested)
    }

    @MainActor
    func testDisablingPersistsIntentAndUnregisters() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLaunchAtLoginService(status: .enabled)
        let controller = LaunchAtLoginController(
            service: service,
            defaults: defaults,
            installContext: eligibleContext
        )

        controller.setRequested(false)

        XCTAssertFalse(controller.isRequested)
        XCTAssertFalse(defaults.bool(forKey: LaunchAtLoginController.requestedDefaultsKey))
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.status, .off)
    }

    @MainActor
    func testRegistrationErrorIsAStateAndOffersSystemSettings() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestError.denied
        let controller = LaunchAtLoginController(
            service: service,
            defaults: defaults,
            installContext: eligibleContext
        )

        controller.setRequested(true)

        guard case .registrationError(let message) = controller.status else {
            return XCTFail("Expected registration-error state, got \(controller.status)")
        }
        XCTAssertTrue(message.contains("Couldn’t enable Launch at Login"))
        XCTAssertTrue(controller.status.needsSystemSettings)
        XCTAssertTrue(controller.isRequested)
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginController.requestedDefaultsKey))

        controller.openSystemSettings()
        XCTAssertEqual(service.openSettingsCallCount, 1)
    }

    @MainActor
    func testIneligibleCopyNeverRegistersEvenWhenIntentWasSaved() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: LaunchAtLoginController.requestedDefaultsKey)
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(
            service: service,
            defaults: defaults,
            installContext: {
                self.context(path: "/Volumes/Gaugelet/Gaugelet.app", isVolumeReadOnly: true)
            }
        )

        XCTAssertEqual(
            controller.status,
            .unavailable(message: "Move Gaugelet to Applications first.")
        )
        XCTAssertFalse(controller.canChangeRequest)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    private func context(
        path: String,
        isVolumeReadOnly: Bool = false,
        isTranslocated: Bool = false
    ) -> LaunchAtLoginInstallContext {
        LaunchAtLoginInstallContext(
            bundleURL: URL(fileURLWithPath: path),
            isVolumeReadOnly: isVolumeReadOnly,
            isTranslocated: isTranslocated
        )
    }

    private func eligibleContext() -> LaunchAtLoginInstallContext {
        LaunchAtLoginInstallContext(
            bundleURL: URL(fileURLWithPath: "/Applications/Gaugelet.app"),
            isVolumeReadOnly: false,
            isTranslocated: false
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "GaugeletLaunchAtLoginTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private enum TestError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Registration denied for testing"
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginServiceStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}
