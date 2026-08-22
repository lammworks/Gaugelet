import AppKit
import SwiftUI

enum GaugeletPalette {
    static let copper = adaptiveColor(
        light: NSColor(red: 0.64, green: 0.31, blue: 0.16, alpha: 1),
        dark: NSColor(red: 0.88, green: 0.56, blue: 0.37, alpha: 1),
        name: "GaugeletCopper"
    )
    static let coral = adaptiveColor(
        light: NSColor(red: 0.68, green: 0.20, blue: 0.18, alpha: 1),
        dark: NSColor(red: 0.94, green: 0.43, blue: 0.39, alpha: 1),
        name: "GaugeletCoral"
    )
    static let glassEdge = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.58),
        dark: NSColor.white.withAlphaComponent(0.16),
        name: "GaugeletGlassEdge"
    )
    static let prominentButtonLabel = adaptiveColor(
        light: NSColor.white,
        dark: NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1),
        name: "GaugeletProminentButtonLabel"
    )

    static func accent(for style: GaugeletIconStyle) -> Color {
        let palette = style.accentPalette
        return adaptiveColor(
            light: nsColor(rgb: palette.lightRGB),
            dark: nsColor(rgb: palette.darkRGB),
            name: "GaugeletAccent-\(style.rawValue)"
        )
    }

    private static func nsColor(rgb: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor, name: String) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

private struct GaugeletAccentEnvironmentKey: EnvironmentKey {
    static let defaultValue = GaugeletPalette.accent(for: .core)
}

private extension EnvironmentValues {
    var gaugeletAccent: Color {
        get { self[GaugeletAccentEnvironmentKey.self] }
        set { self[GaugeletAccentEnvironmentKey.self] = newValue }
    }
}

struct UsagePopoverRoot: View {
    @ObservedObject var store: UsageStore
    let onHoverChanged: (Bool) -> Void
    let onCheckForUpdates: () -> Void
    let usesStandaloneGlass: Bool

    @State private var showingSettings: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        store: UsageStore,
        onHoverChanged: @escaping (Bool) -> Void,
        onCheckForUpdates: @escaping () -> Void,
        usesStandaloneGlass: Bool,
        initiallyShowsSettings: Bool = false
    ) {
        self.store = store
        self.onHoverChanged = onHoverChanged
        self.onCheckForUpdates = onCheckForUpdates
        self.usesStandaloneGlass = usesStandaloneGlass
        _showingSettings = State(initialValue: initiallyShowsSettings)
    }

    var body: some View {
        ZStack {
            Group {
                if usesStandaloneGlass {
                    GaugeletGlassBackground()
                } else {
                    Color.clear
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()
                    .opacity(0.35)

                Group {
                    if showingSettings {
                        SettingsView(
                            store: store,
                            onCheckForUpdates: onCheckForUpdates
                        )
                            .transition(.opacity)
                    } else {
                        UsageDashboard(store: store)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showingSettings)
            }
        }
        .frame(width: 336, height: 466)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.gaugeletAccent, accent)
        .tint(accent)
        .onHover(perform: onHoverChanged)
    }

    private var accent: Color {
        GaugeletPalette.accent(for: store.iconStyle)
    }

    private var header: some View {
        HStack(spacing: 10) {
            GaugeletIconView(style: store.iconStyle, size: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Gaugelet")
                    .font(.system(size: 14, weight: .semibold))
                Text("ChatGPT plan usage")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(store.state.badgeTitle)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.12), in: Capsule())
                .accessibilityLabel(store.state.badgeTitle.lowercased())

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "xmark" : "gearshape")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(showingSettings ? "Close settings" : "Settings")
            .accessibilityLabel(showingSettings ? "Close settings" : "Open settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var badgeColor: Color {
        switch store.state {
        case .stale, .unavailable:
            GaugeletPalette.coral
        case .loading:
            .secondary
        case .live:
            accent
        case .demo:
            GaugeletPalette.copper
        }
    }
}

private struct GaugeletIconView: View {
    let style: GaugeletIconStyle
    let size: CGFloat

    private var accent: Color {
        GaugeletPalette.accent(for: style)
    }

    private var contentScale: CGFloat {
        style == .core ? 1.12 : 1.0
    }

    var body: some View {
        Group {
            if let image = GaugeletAppIcon.image(for: style) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(contentScale)
            } else {
                ZStack {
                    accent.opacity(0.14)
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(GaugeletPalette.glassEdge.opacity(0.65), lineWidth: 0.6)
        }
    }
}

private struct GaugeletGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.gaugeletAccent) private var accent

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        } else {
#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        .regular.tint(accent.opacity(0.055)),
                        in: .rect(cornerRadius: 18)
                    )
            } else {
                materialBackground
            }
#else
            materialBackground
#endif
        }
    }

    private var materialBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(GaugeletPalette.glassEdge, lineWidth: 0.75)
            }
    }
}

private struct UsageDashboard: View {
    @ObservedObject var store: UsageStore
    @Environment(\.gaugeletAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            switch store.state {
            case .loading:
                connectionStatusContent(
                    title: "Connecting to Codex",
                    message: store.state.sourceDetail,
                    symbol: "arrow.triangle.2.circlepath",
                    showsProgress: true,
                    offersRetry: false
                )

            case .unavailable(let errorMessage):
                connectionStatusContent(
                    title: "Live usage unavailable",
                    message: errorMessage,
                    symbol: "exclamationmark.triangle",
                    showsProgress: false,
                    offersRetry: true
                )

            case .live(let snapshot), .demo(let snapshot), .stale(let snapshot, _, _):
                if snapshot.isSignedIn, let closest = snapshot.closestLimit {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        dashboardContent(snapshot: snapshot, closest: closest, now: context.date)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                } else {
                    signedOutContent(snapshot: snapshot)
                }
            }
        }
        .padding(16)
    }

    private func dashboardContent(
        snapshot: UsageSnapshot,
        closest: UsageLimit,
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHATGPT PLAN USAGE")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.65)
                        .foregroundStyle(.secondary)
                    Text(snapshot.planName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 22, height: 22)
                        .accessibilityLabel("Refreshing usage")
                } else {
                    Button {
                        store.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Refresh usage")
                    .accessibilityLabel("Refresh usage")
                }
            }

            Text("MOST CONSTRAINED RETURNED LIMIT")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.65)
                .foregroundStyle(.secondary)

            PrimaryLimitCard(
                limit: closest,
                warningThreshold: store.warningThreshold,
                now: now
            )

            if !snapshot.otherLimits.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("OTHER RETURNED LIMITS")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.65)
                        .foregroundStyle(.secondary)

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(snapshot.otherLimits.enumerated()), id: \.element.id) { index, limit in
                                if index > 0 {
                                    Divider()
                                        .opacity(0.32)
                                }
                                LimitRow(
                                    limit: limit,
                                    warningThreshold: store.warningThreshold,
                                    now: now
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(maxHeight: 126)
                    .scrollIndicators(.visible)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(GaugeletPalette.glassEdge.opacity(0.62), lineWidth: 0.75)
                    }
                }
            }

            Spacer(minLength: 0)

            stateNotice
            footer(snapshot: snapshot)
        }
    }

    private func connectionStatusContent(
        title: String,
        message: String,
        symbol: String,
        showsProgress: Bool,
        offersRetry: Bool
    ) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill((offersRetry ? GaugeletPalette.coral : accent).opacity(0.13))
                if showsProgress {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(accent)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(GaugeletPalette.coral)
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityLabel(showsProgress ? "Connecting" : "Live usage unavailable")

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 14)

            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .lineLimit(6)

            if offersRetry {
                HStack(spacing: 8) {
                    Button {
                        store.refresh()
                    } label: {
                        Text("Retry")
                            .foregroundStyle(GaugeletPalette.prominentButtonLabel)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Button("Codex setup") {
                        store.open(.codexSetup)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.regular)
                .padding(.top, 16)
            }

            Spacer()

            Text(offersRetry
                ? "Install the Codex CLI and sign in, then retry. Demo remains optional in Settings."
                : "No usage value is shown until Codex responds.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func signedOutContent(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accent.opacity(0.13))
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(accent)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Text(snapshot.source == .demo ? "Signed-out demo" : "Codex is not connected")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 14)

            Text(snapshot.source == .demo
                ? "This preview contains demo data only. No account information is being read."
                : "Sign in to Codex, then refresh Gaugelet to read live usage.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 16)
                .padding(.top, 6)

            if snapshot.source != .demo {
                Button("Codex setup guide") {
                    store.open(.codexSetup)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.regular)
                .padding(.top, 16)
            }

            Spacer()

            stateNotice
        }
    }

    @ViewBuilder
    private var stateNotice: some View {
        switch store.state {
        case .stale:
            compactNotice(
                title: "Showing the last live update",
                symbol: "exclamationmark.triangle",
                color: GaugeletPalette.coral
            )
        case .demo:
            compactNotice(
                title: "Demo data — not your account",
                symbol: "testtube.2",
                color: GaugeletPalette.copper
            )
        case .loading, .live, .unavailable:
            EmptyView()
        }
    }

    private func compactNotice(title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHint(store.state.sourceDetail)
    }

    private func footer(snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(store.state.badgeTitle == "STALE" ? "Last live update" : "Updated")
            Text(snapshot.lastUpdated, style: .relative)
            Text("5 min refresh")
                .help("Gaugelet asks Codex for a fresh usage snapshot every five minutes.")
            Label("Read-only", systemImage: "lock")
                .labelStyle(.titleAndIcon)
                .help(store.state.sourceDetail)
            Spacer()
            Button("Open ChatGPT") {
                store.open(.chatGPT)
            }
            .buttonStyle(.link)
            .foregroundStyle(accent)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

private struct PrimaryLimitCard: View {
    let limit: UsageLimit
    let warningThreshold: Int
    let now: Date
    @Environment(\.gaugeletAccent) private var accent

    private var tone: UsageTone {
        limit.tone(warningThreshold: warningThreshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(limit.displayContext ?? "General usage")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(limit.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text(primaryValue)
                        .font(.system(size: limit.blockedReason == nil ? 28 : 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                    Text(primaryValueCaption)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            RemainingProgressBar(fraction: limit.remainingFraction, tone: tone)
                .frame(height: 7)

            Label(
                limit.blockedReason ?? limit.resetDescription(from: now),
                systemImage: limit.blockedReason == nil ? "clock" : "exclamationmark.circle"
            )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GaugeletPalette.glassEdge.opacity(0.72), lineWidth: 0.75)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var primaryValue: String {
        if limit.blockedReason != nil { return "BLOCKED" }
        if limit.isCapped {
            return limit.resetDate?.gaugeletCountdownValue(from: now) ?? "0%"
        }
        return "\(limit.clampedRemainingPercent)%"
    }

    private var primaryValueCaption: String {
        if limit.blockedReason != nil { return "unavailable" }
        if limit.isCapped { return limit.resetDate == nil ? "limit reached" : "until reset" }
        return "left"
    }

    private var accessibilitySummary: String {
        if let blockedReason = limit.blockedReason {
            return "\(limit.displayName), \(blockedReason), \(limit.resetDescription(from: now))"
        }
        return "\(limit.displayName), \(limit.clampedRemainingPercent) percent left, \(limit.resetDescription(from: now))"
    }

    private var color: Color {
        switch tone {
        case .comfortable: accent
        case .warning: GaugeletPalette.copper
        case .critical: GaugeletPalette.coral
        case .unavailable: .secondary
        }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit
    let warningThreshold: Int
    let now: Date
    @Environment(\.gaugeletAccent) private var accent

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(limit.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(limitRowDetail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(limit.blockedReason == nil ? "\(limit.clampedRemainingPercent)% left" : "Unavailable")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            RemainingProgressBar(
                fraction: limit.remainingFraction,
                tone: limit.tone(warningThreshold: warningThreshold)
            )
            .frame(height: 5)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var limitRowDetail: String {
        [limit.displayContext, limit.resetDescription(from: now)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var color: Color {
        switch limit.tone(warningThreshold: warningThreshold) {
        case .comfortable: accent
        case .warning: GaugeletPalette.copper
        case .critical: GaugeletPalette.coral
        case .unavailable: .secondary
        }
    }
}

private struct RemainingProgressBar: View {
    let fraction: Double
    let tone: UsageTone
    @Environment(\.gaugeletAccent) private var accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.10))
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), fraction > 0 ? 3 : 0))
            }
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch tone {
        case .comfortable: accent
        case .warning: GaugeletPalette.copper
        case .critical: GaugeletPalette.coral
        case .unavailable: .secondary
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var store: UsageStore
    let onCheckForUpdates: () -> Void
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @Environment(\.gaugeletAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.system(size: 17, weight: .semibold))

                settingsGroup("BEHAVIOR") {
                    Toggle("Show percentage", isOn: $store.showPercentageInMenuBar)
                    Divider()
                    Toggle("Open on hover", isOn: $store.hoverToOpen)
                    Divider()
                    launchAtLoginRow
                    Divider()
                    HStack {
                        Text("Running low at")
                        Spacer()
                        Stepper(value: $store.warningThreshold, in: 5...50, step: 5) {
                            Text("\(store.warningThreshold)%")
                                .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                        }
                    }
                    Divider()
                    Toggle("Usage alerts", isOn: $store.usageNotificationsEnabled)
                    Text("Get a macOS alert when a live limit drops below \(store.warningThreshold)% or is reached. Gaugelet never alerts for demo or stale data.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup("DATA SOURCE") {
                    Picker("Source", selection: $store.sourcePreference) {
                        ForEach(UsageSourcePreference.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if store.sourcePreference == .demo {
                        Divider()
                        Picker("Preview state", selection: $store.scenario) {
                            ForEach(DemoScenario.allCases) { scenario in
                                Text(scenario.title).tag(scenario)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider()

                    Text(store.sourcePreference == .demo
                        ? "Preview Gaugelet without reading an account."
                        : "Gaugelet reads plan limits from Codex on this Mac. Authentication stays with Codex.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup("APPEARANCE") {
                    HStack {
                        Text("In-app icon")
                        Spacer()
                        Text(store.iconStyle.title)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 52, maximum: 56),
                                spacing: 9,
                                alignment: .center
                            )
                        ],
                        alignment: .center,
                        spacing: 9
                    ) {
                        ForEach(GaugeletIconStyle.allCases) { style in
                            Button {
                                store.iconStyle = style
                            } label: {
                                GaugeletIconView(style: style, size: 44)
                                    .padding(4)
                                    .background(
                                        store.iconStyle == style
                                            ? accent.opacity(0.17)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                store.iconStyle == style
                                                    ? accent.opacity(0.85)
                                                    : Color.clear,
                                                lineWidth: 2
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(style.title)
                            .accessibilityLabel("Use the \(style.title) in-app icon")
                            .accessibilityAddTraits(store.iconStyle == style ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Text("Themes change Gaugelet’s in-app appearance. The menu bar uses a clean adaptive gauge; Finder and notifications use the stable Core icon.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup("ABOUT") {
                    HStack {
                        GaugeletIconView(style: store.iconStyle, size: 28)
                            .accessibilityHidden(true)
                        Text("Gaugelet")
                            .fontWeight(.medium)
                        Spacer()
                        Text(GaugeletBuildInfo.versionAndBuild)
                            .foregroundStyle(.secondary)
                    }

                    Text("Built by LammWorks")
                        .font(.system(size: 10.5, weight: .medium))

                    Text("Gaugelet can check daily after you opt in. Download and installation always require confirmation.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack(spacing: 6) {
                        aboutAction(
                            "Check for Updates",
                            symbol: "arrow.down.circle",
                            action: onCheckForUpdates
                        )
                        aboutLink("View All Releases", symbol: "shippingbox", destination: .releases)
                    }
                    HStack(spacing: 6) {
                        aboutLink("Buy me a coffee", symbol: "cup.and.saucer", destination: .buyMeACoffee)
                        aboutLink("Privacy", symbol: "hand.raised", destination: .privacy)
                    }
                    HStack(spacing: 6) {
                        aboutLink("Source", symbol: "chevron.left.forwardslash.chevron.right", destination: .source)
                        aboutLink("Codex setup", symbol: "book", destination: .codexSetup)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Private by design", systemImage: "lock.shield")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Codex owns authentication. Gaugelet stores no credentials, analytics, or usage history.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(0.055))
                        .allowsHitTesting(false)
                }

                HStack {
                    Text("Unofficial · Not affiliated with OpenAI")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Quit Gaugelet") {
                        store.quit()
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(GaugeletPalette.coral)
                }
            }
            .padding(16)
        }
        .font(.system(size: 11.5))
        .onAppear {
            launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isRequested },
                    set: { launchAtLogin.setRequested($0) }
                ))
                .disabled(!launchAtLogin.canChangeRequest)

                Spacer(minLength: 8)

                Text(launchAtLogin.status.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(launchAtLogin.status.isEnabled ? accent : .secondary)
                    .accessibilityLabel("Launch at Login status: \(launchAtLogin.status.title)")
            }

            if let detail = launchAtLogin.status.detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if launchAtLogin.status.needsSystemSettings {
                Button("Open Login Items Settings") {
                    launchAtLogin.openSystemSettings()
                }
                .buttonStyle(.link)
                .help("Open macOS Login Items settings")
            }

        }
    }

    private func aboutAction(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            aboutButtonLabel(title, symbol: symbol)
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .help(title)
        .accessibilityLabel(title)
    }

    private func aboutLink(
        _ title: String,
        symbol: String,
        destination: GaugeletLink
    ) -> some View {
        Button {
            store.open(destination)
        } label: {
            aboutButtonLabel(title, symbol: symbol)
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .help("Open \(title)")
        .accessibilityLabel("Open \(title)")
    }

    private func aboutButtonLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .frame(width: 13)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.65)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                content()
            }
            .padding(11)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(GaugeletPalette.glassEdge.opacity(0.68), lineWidth: 0.75)
            }
        }
    }
}

extension Date {
    func gaugeletCountdownValue(from now: Date = Date()) -> String {
        let minutes = max(Int(timeIntervalSince(now) / 60), 0)
        if minutes < 60 { return "\(max(minutes, 1))m" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }

        return "\(hours / 24)d"
    }
}
