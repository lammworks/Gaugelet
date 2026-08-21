import AppKit
import Foundation
import XCTest
@testable import Gaugelet

final class GaugeletThemeTests: XCTestCase {
    func testEveryIconStyleHasTheExpectedAccentPalette() {
        XCTAssertEqual(
            GaugeletIconStyle.allCases.map(\.accentPalette),
            [
                GaugeletAccentPalette(lightRGB: 0x1D72C7, darkRGB: 0x60BAF4),
                GaugeletAccentPalette(lightRGB: 0x6272A4, darkRGB: 0xBD93F9),
                GaugeletAccentPalette(lightRGB: 0x6B5600, darkRGB: 0xFFD166),
                GaugeletAccentPalette(lightRGB: 0x277247, darkRGB: 0x73D69A),
                GaugeletAccentPalette(lightRGB: 0x4D5158, darkRGB: 0xD1D5DB),
                GaugeletAccentPalette(lightRGB: 0x0F6795, darkRGB: 0x55C8F7),
                GaugeletAccentPalette(lightRGB: 0xDB1F7E, darkRGB: 0x5FFBF1)
            ]
        )
    }

    func testSignedOutDemoUsesSignedOutMenuBarPresentation() {
        let snapshot = DemoUsageProvider.snapshot(for: .signedOut)

        XCTAssertEqual(
            GaugeletMenuBarPresentation.iconState(for: .demo(snapshot)),
            GaugeletMenuBarIconState(mode: .signedOut, percent: nil)
        )
    }

    func testAccentForegroundsAndProminentButtonLabelsMaintainReadableContrast() {
        for style in GaugeletIconStyle.allCases {
            let palette = style.accentPalette
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.lightRGB, 0xFFFFFF),
                4.5,
                "\(style.title) light accent must remain legible and support a white button label"
            )
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.darkRGB, 0x1E1E1E),
                4.5,
                "\(style.title) dark accent must remain legible and support a dark button label"
            )
        }
    }

    @MainActor
    func testLegacyFinderOverrideIsClearedOnceAndFinderIsNotified() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("GaugeletSystemIconTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let legacyIconURL = directory.appendingPathComponent("Icon\r", isDirectory: false)
        try Data().write(to: legacyIconURL)

        var clearedPath: String?
        var notifiedPath: String?
        let didClear = GaugeletSystemIcon.clearLegacyFinderOverride(
            at: directory,
            fileManager: fileManager,
            clearIcon: { path in
                clearedPath = path
                try? fileManager.removeItem(at: legacyIconURL)
                return true
            },
            noteFileSystemChanged: { path in
                notifiedPath = path
            }
        )

        XCTAssertTrue(didClear)
        XCTAssertEqual(clearedPath, directory.path)
        XCTAssertEqual(notifiedPath, directory.path)
        XCTAssertFalse(GaugeletSystemIcon.hasLegacyFinderOverride(at: directory))

        XCTAssertFalse(
            GaugeletSystemIcon.clearLegacyFinderOverride(
                at: directory,
                fileManager: fileManager,
                clearIcon: { _ in
                    XCTFail("A cleared Finder override must not be removed again")
                    return false
                },
                noteFileSystemChanged: { _ in
                    XCTFail("Finder must not be notified without a legacy override")
                }
            )
        )
    }

    @MainActor
    func testFailedLegacyFinderOverrideCleanupLeavesFinderUnchanged() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("GaugeletSystemIconTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        try Data().write(to: directory.appendingPathComponent("Icon\r", isDirectory: false))
        var didNotifyFinder = false

        XCTAssertFalse(
            GaugeletSystemIcon.clearLegacyFinderOverride(
                at: directory,
                fileManager: fileManager,
                clearIcon: { _ in false },
                noteFileSystemChanged: { _ in didNotifyFinder = true }
            )
        )
        XCTAssertFalse(didNotifyFinder)
        XCTAssertTrue(GaugeletSystemIcon.hasLegacyFinderOverride(at: directory))
    }

    private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ rgb: UInt32) -> Double {
        let red = linearized(Double((rgb >> 16) & 0xFF) / 255)
        let green = linearized(Double((rgb >> 8) & 0xFF) / 255)
        let blue = linearized(Double(rgb & 0xFF) / 255)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private func linearized(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }
}
