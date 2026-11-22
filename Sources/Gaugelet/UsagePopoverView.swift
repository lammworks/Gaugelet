import Charts
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

enum GaugeletPopoverMetrics {
    static let width: CGFloat = 336

    static var maxHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        return max(420, visible - 28)
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

            ViewThatFits(in: .vertical) {
                popoverColumn
                ScrollView(.vertical) {
                    popoverColumn
                }
            }
        }
        .frame(width: GaugeletPopoverMetrics.width)
        .frame(maxHeight: GaugeletPopoverMetrics.maxHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.gaugeletAccent, accent)
        .tint(accent)
        .onHover(perform: onHoverChanged)
    }

    private var accent: Color {
        GaugeletPalette.accent(for: store.iconStyle)
    }

    private var popoverColumn: some View {
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
            GaugeletIconView(style: store.iconStyle, size: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Gaugelet")
                    .font(.system(size: 14, weight: .semibold))
                Text(store.selectedPlan.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(headerBadge)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.12), in: Capsule())
                .accessibilityLabel(headerBadge.lowercased())

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
        .padding(.top, 10)

        Picker("Plan", selection: $store.selectedPlan) {
            ForEach(UsagePlan.allCases) { plan in
                Text(plan.title).tag(plan)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
            .accessibilityLabel("Usage plan")
        }
    }

    private var headerBadge: String {
        store.showsCursorEnable ? "OFF" : store.presentedState.badgeTitle
    }

    private var badgeColor: Color {
        if store.showsCursorEnable { return .secondary }
        switch store.presentedState {
        case .stale, .unavailable:
            return GaugeletPalette.coral
        case .loading:
            return .secondary
        case .live(let snapshot):
            return snapshot.isSignedIn ? accent : .secondary
        case .demo:
            return GaugeletPalette.copper
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
            if store.showsCursorEnable {
                cursorEnableContent
            } else {
                switch store.presentedState {
                case .loading:
                    connectionStatusContent(
                        title: store.selectedPlan == .cursor ? "Connecting to Cursor" : "Connecting to Codex",
                        message: store.presentedState.detail(for: store.selectedPlan),
                        symbol: "arrow.triangle.2.circlepath",
                        showsProgress: true,
                        offersRetry: false
                    )

                case .unavailable(let errorMessage):
                    connectionStatusContent(
                        title: unavailableTitle(message: errorMessage),
                        message: errorMessage,
                        symbol: "exclamationmark.triangle",
                        showsProgress: false,
                        offersRetry: true
                    )

                case .live(let snapshot), .demo(let snapshot), .stale(let snapshot, _, _):
                    if snapshot.isSignedIn {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            dashboardContent(snapshot: snapshot, now: context.date)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    } else {
                        signedOutContent(snapshot: snapshot)
                    }
                }
            }
        }
        .padding(16)
    }

    private func dashboardContent(snapshot: UsageSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ALLOWANCE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                    Text(snapshot.planName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.presentedIsRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button { store.refreshPresented() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh usage")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                    if snapshot.orderedLimits.isEmpty {
                        Text("Allowance windows unavailable")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if let panel = snapshot.grokPanel {
                        grokPanel(panel)
                    }
                    if !snapshot.grokProductShares.isEmpty {
                        grokPoolShares(snapshot)
                    }
                    VStack(spacing: 0) {
                        ForEach(snapshot.orderedLimits) { limit in
                            HStack(spacing: 8) {
                                AllowanceRow(limit: limit, warningThreshold: store.warningThreshold, now: now)
                                Button {
                                    store.pinnedLimitID = store.pinnedLimitID == limit.id ? "" : limit.id
                                } label: {
                                    Image(systemName: store.pinnedLimitID == limit.id ? "pin.fill" : "pin")
                                        .font(.system(size: 11))
                                        .foregroundStyle(store.pinnedLimitID == limit.id ? accent : .secondary)
                                        .frame(width: 24, height: 34)
                                }
                                .buttonStyle(.plain)
                                .help(store.pinnedLimitID == limit.id ? "Use default menu-bar counter" : "Pin to menu bar")
                                .accessibilityLabel("\(store.pinnedLimitID == limit.id ? "Unpin" : "Pin") \(limit.compactName)")
                            }
                            if limit.id != snapshot.orderedLimits.last?.id { Divider().opacity(0.3) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    if snapshot.omittedLimitCount > 0 {
                        Text("\(snapshot.omittedLimitCount) additional windows · view in Manage usage")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if !store.pinnedLimitID.isEmpty && store.menuBarLimit == nil {
                        HStack {
                            Text("Pinned counter unavailable").foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear pin") { store.pinnedLimitID = "" }.buttonStyle(.link)
                        }.font(.system(size: 10.5))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        if snapshot.plan != .cursor || snapshot.resetCredits != nil {
                            HStack {
                                Label("Resets", systemImage: "arrow.counterclockwise")
                                Spacer()
                                Text(snapshot.resetCredits.map { "\($0.availableCount) available" } ?? "Unavailable")
                                    .monospacedDigit()
                            }
                            if let expiry = snapshot.resetCredits?.earliestKnownExpiry {
                                Text("Next known expiry \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(snapshot.credits) { credit in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(credit.label).lineLimit(1)
                                    Spacer()
                                    Text(credit.displayValue).monospacedDigit()
                                }
                                if let detail = credit.detail {
                                    Text(detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Manage usage") { store.openManageUsage(for: snapshot) }.buttonStyle(.link)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 2)

                    if store.activityEnabled && snapshot.plan == .chatgpt {
                        Divider().opacity(0.4)
                        activityContent
                    }
                }
            stateNotice
            footer(snapshot: snapshot)
        }
    }

    @ViewBuilder private var activityContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOKEN ACTIVITY").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
            switch store.activityState {
            case .disabled:
                EmptyView()
            case .loading:
                ProgressView().controlSize(.small)
            case .unavailable:
                Text("Activity unavailable").foregroundStyle(.secondary)
            case .available(let activity):
                if let days = activity.days, !days.isEmpty {
                    Chart(days) { day in
                        BarMark(x: .value("Date", String(day.date.suffix(5))), y: .value("Tokens", day.tokens))
                            .foregroundStyle(accent)
                            .accessibilityLabel(day.date)
                            .accessibilityValue("\(day.tokens) tokens")
                    }
                    .chartXAxis { AxisMarks(values: .automatic) }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .frame(height: 85)
                    ForEach(days.reversed()) { day in
                        HStack {
                            Text(day.date).foregroundStyle(.secondary)
                            Spacer()
                            Text(day.tokens.formatted()).monospacedDigit()
                        }
                    }
                } else {
                    Text(activity.days == nil ? "Daily activity unavailable" : "No reported daily activity")
                        .foregroundStyle(.secondary)
                }
                if let lifetime = activity.lifetimeTokens {
                    HStack {
                        Text("Lifetime tokens").foregroundStyle(.secondary)
                        Spacer()
                        Text(lifetime.formatted()).monospacedDigit()
                    }
                }
                Text("Checked \(activity.lastUpdated.formatted(date: .omitted, time: .shortened)) · reported days")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10.5))
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
                .lineLimit(8)

            if offersRetry {
                HStack(spacing: 8) {
            Button {
                store.refreshPresented()
            } label: {
                        Text("Retry")
                            .foregroundStyle(GaugeletPalette.prominentButtonLabel)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Button(store.selectedPlan == .cursor ? "Cursor dashboard" : "Codex setup") {
                        store.open(store.selectedPlan == .cursor ? .cursorDashboard : .codexSetup)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.regular)
                .padding(.top, 16)
            }

            Spacer()

            Text(offersRetry
                ? (store.selectedPlan == .cursor
                    ? "Open Cursor and sign in, then retry. Demo remains optional in Settings."
                    : "Install the Codex CLI and sign in, then retry. Demo remains optional in Settings.")
                : (store.selectedPlan == .cursor
                    ? "No usage value is shown until Cursor responds."
                    : "No usage value is shown until Codex responds."))
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

            Text(snapshot.signedOutHeading)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 14)

            Text(snapshot.signedOutGuidance)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(8)

            if let panel = snapshot.grokPanel, case .login(let reason, let pathLabel) = panel {
                if snapshot.source == .cursorPlan {
                    Button("Open Cursor") {
                        store.open(.cursorDashboard)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.regular)
                    .padding(.top, 16)
                }
                grokLoginCard(reason: reason, pathLabel: pathLabel)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
            } else if snapshot.source != .demo {
                Button(signedOutButtonTitle(for: snapshot)) {
                    store.open(signedOutLink(for: snapshot))
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

    private var cursorEnableContent: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(accent.opacity(0.13))
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(accent)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Text("Cursor plan usage is off")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 14)

            Text("Gaugelet can read the Cursor plan from the Cursor sign-in on this Mac, and Grok credits from the local Grok sign-in. It uses those tokens for the usage request and does not save them.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            Button("Enable Cursor usage") {
                store.cursorUsageEnabled = true
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.regular)
            .padding(.top, 16)
            Spacer()
        }
    }

    private func unavailableTitle(message: String) -> String {
        guard store.selectedPlan == .cursor else { return "Live usage unavailable" }
        return message.localizedCaseInsensitiveContains("grok") ? "Grok usage unavailable" : "Cursor usage unavailable"
    }

    private func signedOutButtonTitle(for snapshot: UsageSnapshot) -> String {
        if snapshot.source == .grokPlan { return "Open Grok usage" }
        return snapshot.plan == .cursor ? "Open Cursor" : "Codex setup guide"
    }

    private func signedOutLink(for snapshot: UsageSnapshot) -> GaugeletLink {
        if snapshot.source == .grokPlan { return .grokDashboard }
        return snapshot.plan == .cursor ? .cursorDashboard : .codexSetup
    }

    @ViewBuilder
    private var stateNotice: some View {
        switch store.presentedState {
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
            .accessibilityHint(store.presentedState.detail(for: store.selectedPlan))
    }

    @ViewBuilder
    private func grokPanel(_ panel: GrokPanel) -> some View {
        switch panel {
        case .login(let reason, let pathLabel):
            grokLoginCard(reason: reason, pathLabel: pathLabel)
        case .status(let message):
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func grokLoginCard(reason: String, pathLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run this in Terminal")
                .font(.system(size: 11, weight: .semibold))
            Text(reason)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(GrokPanel.command)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            Text("Gaugelet reads \(pathLabel) afterward. It does not refresh tokens.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Copy command") { copyGrokLoginCommand() }
                Button("Open Terminal") { openTerminal() }
                Button("Retry") { store.refreshPresented() }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func grokPoolShares(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GROK BUILD AND GROK")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
            Text("Grok Build is the grok coding CLI. It uses this same weekly plan. It is not a separate allowance, and it is not the Cursor app meter.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PoolShareBar(shares: snapshot.grokProductShares)
                .frame(height: 8)
            ForEach(snapshot.grokProductShares) { share in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(share.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Text(share.detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(share.usedPercent)% of plan")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func copyGrokLoginCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(GrokPanel.command, forType: .string)
    }

    private func openTerminal() {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(terminal)
    }

    private func footer(snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 4) {
            Text(store.presentedState.badgeTitle == "STALE" ? "Last live check" : "Checked")
            Text(snapshot.lastUpdated, style: .relative)
            Text("ago")
            Spacer()
            Label("Read-only", systemImage: "lock")
                .help(snapshot.plan == .cursor
                    ? "Grok and Cursor plan usage. Background refresh adapts to power; Gaugelet does not buy credits or change the plan."
                    : "ChatGPT Work and Codex allowance. Background refresh adapts to power; refreshes on wake, open, and reset.")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

}

private struct PoolShareBar: View {
    let shares: [GrokProductShare]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    Rectangle()
                        .fill(color(index))
                        .frame(width: max(proxy.size.width * CGFloat(share.usedPercent) / 100, share.usedPercent > 0 ? 2 : 0))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.08))
        }
        .clipShape(Capsule())
        .accessibilityLabel("Weekly plan shares")
    }

    private func color(_ index: Int) -> Color {
        let colors: [Color] = [
            GaugeletPalette.copper,
            GaugeletPalette.coral,
            Color.blue.opacity(0.75),
            Color.teal.opacity(0.8),
            Color.purple.opacity(0.7),
            Color.orange.opacity(0.8)
        ]
        return colors[index % colors.count]
    }
}

private struct AllowanceRow: View {
    let limit: UsageLimit
    let warningThreshold: Int
    let now: Date
    @Environment(\.gaugeletAccent) private var accent

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(limit.compactName)
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
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .help(limit.contextNote ?? limit.blockedReason ?? limit.name)
        .accessibilityElement(children: .combine)
    }

    private var limitRowDetail: String {
        if limit.id == "cursor:session", let blockedReason = limit.blockedReason {
            return blockedReason
        }
        return [limit.contextNote, limit.blockedReason, limit.resetDescription(from: now)]
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
                    Toggle("Alert when restored", isOn: $store.notifyOnRestore)
                        .disabled(!store.usageNotificationsEnabled)
                    Divider()
                    Toggle("Token activity", isOn: $store.activityEnabled)
                    Text("Account activity stays on this Mac.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup("MENU-BAR COUNTER") {
                    Picker("Counter", selection: $store.pinnedLimitID) {
                        Text("Default").tag("")
                        ForEach(store.menuBarChoices) { limit in
                            Text(limit.id.hasPrefix("cursor:") ? "Cursor · \(limit.compactName)" : limit.compactName)
                                .tag(limit.id)
                        }
                        if !store.pinnedLimitID.isEmpty && store.menuBarLimit == nil {
                            Text("Pinned counter unavailable").tag(store.pinnedLimitID)
                        }
                    }.labelsHidden()
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
                        : "Gaugelet reads ChatGPT plan limits from Codex on this Mac. Authentication stays with Codex.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup("CURSOR PLAN") {
                    Toggle("Read Cursor usage", isOn: $store.cursorUsageEnabled)
                    Text("When this is on, Gaugelet reads the local Cursor access token and the Grok sign-in in ~/.grok/auth.json when that file has one. Each token stays in memory for its usage request and is not saved.")
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
                    Text("Codex owns its authentication. Cursor usage is off until you enable it, and that token is not stored. Gaugelet stores no analytics or usage history.")
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
                    Text("Unofficial · Not affiliated with OpenAI, Cursor, or xAI")
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
        guard let minutes = gaugeletWholeMinutes(from: now) else { return "—" }
        if minutes < 60 { return "\(max(minutes, 1))m" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }

        return "\(hours / 24)d"
    }
}
