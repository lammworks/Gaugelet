import Foundation

private var failureCount = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

private func relativeLuminance(_ rgb: UInt32) -> Double {
    func linearized(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }

    let red = linearized(Double((rgb >> 16) & 0xFF) / 255)
    let green = linearized(Double((rgb >> 8) & 0xFF) / 255)
    let blue = linearized(Double(rgb & 0xFF) / 255)
    return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
}

private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    return (max(firstLuminance, secondLuminance) + 0.05)
        / (min(firstLuminance, secondLuminance) + 0.05)
}

let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
let high = UsageLimit(
    id: "high",
    name: "High",
    remainingPercent: 130,
    resetDate: referenceDate
)
let low = UsageLimit(
    id: "low",
    name: "Low",
    remainingPercent: -10,
    resetDate: referenceDate
)

expect(high.clampedRemainingPercent == 100, "remaining percentage clamps at 100")
expect(low.clampedRemainingPercent == 0, "remaining percentage clamps at zero")

let response = """
{"id":1,"result":{"userAgent":"Codex"}}
{"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000},"secondary":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000},"secondary":null},"spark":{"limitId":"spark","limitName":"Codex Spark","primary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":1894060800},"secondary":null}}}}
"""

do {
    let snapshot = try CodexUsageProvider.parseSnapshot(
        from: Data(response.utf8),
        now: referenceDate
    )
    expect(snapshot.source == .codexAppServer, "App Server source is retained")
    expect(snapshot.limits.count == 2, "all returned buckets are parsed")
    expect(snapshot.closestLimit?.name == "Codex Spark · Weekly", "closest cap sorts by remaining allowance")
    expect(snapshot.closestLimit?.remainingPercent == 20, "used percentage converts to remaining")
} catch {
    failureCount += 1
    FileHandle.standardError.write(Data("FAIL: parser threw \(error)\n".utf8))
}

let responseWithoutResetMetadata = """
{"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":37},"secondary":{"usedPercent":52,"windowDurationMins":null,"resetsAt":null}}}}
"""

do {
    let snapshot = try CodexUsageProvider.parseSnapshot(
        from: Data(responseWithoutResetMetadata.utf8),
        now: referenceDate
    )
    expect(snapshot.limits.count == 2, "windows remain usable without reset metadata")
    expect(snapshot.limits.allSatisfy { $0.resetDate == nil }, "missing reset metadata stays missing")
    expect(snapshot.closestLimit?.name == "Codex · Secondary", "bucket names remain explicit without duration metadata")
} catch {
    failureCount += 1
    FileHandle.standardError.write(Data("FAIL: nullable parser threw \(error)\n".utf8))
}

let blockedResponse = """
{"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":{"usedPercent":30},"secondary":null,"rateLimitReachedType":"workspace_member_credits_depleted"}}}
"""

do {
    let snapshot = try CodexUsageProvider.parseSnapshot(
        from: Data(blockedResponse.utf8),
        now: referenceDate
    )
    expect(snapshot.planName == "ChatGPT Plus", "returned plan type is retained")
    expect(snapshot.closestLimit?.remainingPercent == 70, "blocked state preserves the returned allowance value")
    expect(snapshot.closestLimit?.blockedReason == "Workspace credits depleted", "server blocked state is retained")
    expect(snapshot.closestLimit?.remainingFraction == 0, "blocked limits do not render available progress")
} catch {
    failureCount += 1
    FileHandle.standardError.write(Data("FAIL: blocked-state parser threw \(error)\n".utf8))
}

let nearCapResponse = """
{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":99.6},"secondary":null}}}
"""

do {
    let snapshot = try CodexUsageProvider.parseSnapshot(
        from: Data(nearCapResponse.utf8),
        now: referenceDate
    )
    expect(snapshot.closestLimit?.remainingPercent == 1, "near-cap usage retains a 1 percent floor")
    expect(snapshot.closestLimit?.isCapped == false, "near-cap usage is not reported as capped")
} catch {
    failureCount += 1
    FileHandle.standardError.write(Data("FAIL: near-cap parser threw \(error)\n".utf8))
}

for invalidValue in ["true", "-1", "100.1"] {
    let invalidResponse = """
    {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":\(invalidValue)},"secondary":null}}}
    """
    do {
        _ = try CodexUsageProvider.parseSnapshot(from: Data(invalidResponse.utf8))
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL: invalid usedPercent \(invalidValue) was accepted\n".utf8))
    } catch CodexUsageError.noRateLimits {
        // Expected: malformed values never become credible live usage.
    } catch {
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL: invalid usedPercent returned \(error)\n".utf8))
    }
}

let malformedMetadataResponse = """
{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":37,"windowDurationMins":true,"resetsAt":true},"secondary":null}}}
"""

do {
    let snapshot = try CodexUsageProvider.parseSnapshot(from: Data(malformedMetadataResponse.utf8))
    expect(snapshot.closestLimit?.name == "Codex", "Boolean duration metadata is ignored")
    expect(snapshot.closestLimit?.resetDate == nil, "Boolean reset metadata is ignored")
} catch {
    failureCount += 1
    FileHandle.standardError.write(Data("FAIL: malformed optional metadata threw \(error)\n".utf8))
}

var boundedBuckets: [String: Any] = [:]
for index in 0..<10 {
    boundedBuckets["bucket-\(index)"] = [
        "primary": ["usedPercent": index],
        "secondary": ["usedPercent": index + 1]
    ]
}

do {
    let boundedMessage: [String: Any] = [
        "id": 2,
        "result": ["rateLimitsByLimitId": boundedBuckets]
    ]
    let boundedResponse = try JSONSerialization.data(withJSONObject: boundedMessage)
    let snapshot = try CodexUsageProvider.parseSnapshot(from: boundedResponse)

    expect(snapshot.limits.count == 12, "parser retains the bounded set of most constrained windows")
    expect(snapshot.otherLimits.count == 11, "all non-primary windows remain available to the UI")
} catch {
    failureCount += 1
    FileHandle.standardError.write(Data("FAIL: bounded-window parser threw \(error)\n".utf8))
}

let reset = referenceDate.addingTimeInterval(2 * 60 * 60 + 14 * 60)
expect(reset.gaugeletRelativeReset(from: referenceDate) == "Resets in 2h 14m", "reset label is compact")

let expectedAccentPalettes = [
    GaugeletAccentPalette(lightRGB: 0x1D72C7, darkRGB: 0x60BAF4),
    GaugeletAccentPalette(lightRGB: 0x6272A4, darkRGB: 0xBD93F9),
    GaugeletAccentPalette(lightRGB: 0x6B5600, darkRGB: 0xFFD166),
    GaugeletAccentPalette(lightRGB: 0x277247, darkRGB: 0x73D69A),
    GaugeletAccentPalette(lightRGB: 0x4D5158, darkRGB: 0xD1D5DB),
    GaugeletAccentPalette(lightRGB: 0x0F6795, darkRGB: 0x55C8F7),
    GaugeletAccentPalette(lightRGB: 0xDB1F7E, darkRGB: 0x5FFBF1)
]
expect(
    GaugeletIconStyle.allCases.map(\.accentPalette) == expectedAccentPalettes,
    "every selectable icon keeps its intended adaptive accent"
)
for style in GaugeletIconStyle.allCases {
    expect(
        contrastRatio(style.accentPalette.lightRGB, 0xFFFFFF) >= 4.5,
        "\(style.title) light accent remains readable and supports a white button label"
    )
    expect(
        contrastRatio(style.accentPalette.darkRGB, 0x1E1E1E) >= 4.5,
        "\(style.title) dark accent remains readable and supports a dark button label"
    )
}

if failureCount > 0 {
    exit(1)
}

print("Smoke tests passed")
