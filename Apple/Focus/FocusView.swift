#if os(iOS)
import SwiftUI
import FamilyControls

/// Individual Screen Time controls remain native: opaque selections never reach the web UI.
@MainActor
struct FocusView: View {
    var onClose: () -> Void = {}

    @StateObject private var controller = FocusController()
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var pickerPresented = false
    @State private var draftMode: FocusMode = .block
    @State private var minutesText = "30"
    @State private var loadedDraft = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private var accent: Color { colorScheme == .dark ? Color(red: 213/255, green: 237/255, blue: 157/255) : Color(red: 36/255, green: 78/255, blue: 61/255) }
    private var background: Color { colorScheme == .dark ? Color(red: 15/255, green: 22/255, blue: 18/255) : Color(red: 245/255, green: 244/255, blue: 239/255) }
    private var surface: Color { colorScheme == .dark ? Color(red: 25/255, green: 37/255, blue: 29/255) : Color(red: 255/255, green: 254/255, blue: 250/255) }
    private var border: Color { colorScheme == .dark ? Color(red: 43/255, green: 58/255, blue: 46/255) : Color(red: 226/255, green: 229/255, blue: 218/255) }
    private var accentInk: Color { colorScheme == .dark ? Color(red: 31/255, green: 54/255, blue: 29/255) : Color(red: 247/255, green: 249/255, blue: 238/255) }
    private var minutes: Int? {
        guard let value = Int(minutesText), (1...1440).contains(value) else { return nil }
        return value
    }
    private var canApply: Bool {
        controller.isAuthorized && controller.sharedStorageAvailable && controller.hasReadableConfiguration && controller.selectedCount > 0 && !controller.isBusy && !isSimulator && (draftMode != .dailyLimit || (controller.dailyLimitAvailable && minutes != nil))
    }
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introduction
                    currentStatus
                    if !controller.isAuthorized {
                        permissionCard
                    } else {
                        selectionCard
                        modeCard
                        if draftMode == .dailyLimit { allowanceCard }
                        applyButton
                    }
                    if let message = controller.errorMessage, !message.isEmpty, !isSimulator {
                        notice("Something needs attention", message, symbol: "exclamationmark.circle")
                            .accessibilityIdentifier("focus-error")
                    }
                    if let message = controller.statusMessage, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("focus-status-message")
                    }
                    if !isSimulator && (controller.configuration.mode != .off || controller.isAuthorized || !controller.hasReadableConfiguration) {
                        Button {
                            controller.stop()
                        } label: {
                            Label("Turn off restrictions", systemImage: "lock.open")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("focus-stop")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your choices stay on this iPhone.", systemImage: "hand.raised")
                            .font(.footnote.weight(.medium))
                        Text("These controls are for your own focus. You can turn them off here, or revoke access in iPhone Settings.")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(background)
            .navigationTitle("App limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("focus-done")
                }
            }
            .tint(accent)
            .familyActivityPicker(isPresented: $pickerPresented, selection: $pickerSelection)
            .onChange(of: pickerPresented) { presented in
                if !presented { controller.saveSelection(pickerSelection) }
            }
            .task {
                controller.refresh()
                if !loadedDraft {
                    pickerSelection = controller.configuration.selection
                    draftMode = controller.configuration.mode == .off ? .block : controller.configuration.mode
                    minutesText = String(controller.configuration.dailyMinutes)
                    loadedDraft = true
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { controller.refresh() }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("Make room for what matters.")
                .font(.title2.weight(.semibold))
            Text("Choose distracting apps, then block them now or give yourself a daily usage budget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var currentStatus: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 27)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(colorScheme == .dark ? 0.09 : 0.07), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("focus-current-status")
    }

    private var permissionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(controller.configuration.mode == .off ? "Connect Screen Time" : "Reconnect Screen Time")
                    .font(.headline)
                Text(controller.configuration.mode == .off
                     ? "Approve access on your iPhone to choose which apps to limit. Apple’s app picker keeps the selection private."
                     : "Reconnect to verify and manage your saved boundary. It may still be applied while access is being checked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await controller.requestAuthorization() }
                } label: {
                    HStack(spacing: 9) {
                        if controller.isBusy { ProgressView() }
                        Text(controller.configuration.mode == .off ? "Allow Screen Time access" : "Check Screen Time access")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(isSimulator ? Color.secondary : accentInk)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isBusy || isSimulator)
                .accessibilityIdentifier("focus-authorize")
            }
        }
    }

    private var selectionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("1. Choose distractions")
                        .font(.headline)
                    Spacer()
                    Text("\(controller.selectedCount) selected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                selectionSummary
                Button {
                    pickerSelection = controller.configuration.selection
                    pickerPresented = true
                } label: {
                    Label("Choose apps and categories", systemImage: "square.grid.2x2")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(controller.isBusy || !controller.sharedStorageAvailable || isSimulator)
                .accessibilityIdentifier("focus-choose-apps")
                if controller.configuration.mode != .off {
                    Text("Changing your selection pauses the current restriction. Apply again when you’re ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !controller.sharedStorageAvailable {
                    Text("This build needs its Screen Time setup completed before restrictions can be saved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var selectionSummary: some View {
        let selection = controller.configuration.selection
        return VStack(alignment: .leading, spacing: 7) {
            if controller.selectedCount == 0 {
                Text("Start with the apps that tend to pull you away.")
                    .foregroundStyle(.secondary)
            } else {
                if !selection.applicationTokens.isEmpty {
                    Text("\(selection.applicationTokens.count) app\(selection.applicationTokens.count == 1 ? "" : "s")")
                }
                if !selection.categoryTokens.isEmpty {
                    Text("\(selection.categoryTokens.count) categor\(selection.categoryTokens.count == 1 ? "y" : "ies")")
                }
                if !selection.webDomainTokens.isEmpty {
                    Text("\(selection.webDomainTokens.count) website\(selection.webDomainTokens.count == 1 ? "" : "s")")
                }
            }
        }
        .font(.subheadline)
    }

    private var modeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 15) {
                Text("2. Choose your boundary")
                    .font(.headline)
                modeOption(.block, title: "Block now", detail: "Keep selected apps blocked until you turn this off.", symbol: "lock")
                modeOption(.dailyLimit, title: "Daily usage limit", detail: "Allow a shared daily budget, then block the selection until the next day.", symbol: "hourglass")
                if !controller.dailyLimitAvailable {
                    Text("Daily usage limits require iOS 17.4 or later. Immediate blocking is available on this iOS version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func modeOption(_ mode: FocusMode, title: String, detail: String, symbol: String) -> some View {
        Button {
            draftMode = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .frame(width: 23)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: draftMode == mode ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(14)
            .background(draftMode == mode ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(draftMode == mode ? accent.opacity(0.6) : border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy || (mode == .dailyLimit && !controller.dailyLimitAvailable))
        .accessibilityLabel(title)
        .accessibilityValue(draftMode == mode ? "Selected" : "Not selected")
    }

    private var allowanceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 15) {
                Text("3. Set your daily budget")
                    .font(.headline)
                HStack(spacing: 8) {
                    ForEach([15, 30, 60, 120], id: \.self) { value in
                        Button {
                            minutesText = String(value)
                        } label: {
                            Text(shortMinutes(value))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(minutes == value ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(minutes == value ? accent.opacity(0.6) : border))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(value) minutes")
                    }
                }
                HStack(spacing: 15) {
                    Text("Custom minutes")
                        .font(.subheadline)
                    Spacer()
                    TextField("Minutes", text: $minutesText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 105, minHeight: 44)
                        .accessibilityLabel("Daily limit in minutes")
                }
                if minutes == nil {
                    Text("Enter a whole number from 1 to 1,440 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("This is one combined budget across your selection, including usage already recorded today. A new allowance begins with the next daily interval; Screen Time updates when the phone is used. A block may take a little time to apply after the limit is reached.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var applyButton: some View {
        Button {
            if draftMode == .dailyLimit, let minutes {
                controller.startDailyLimit(minutes: minutes)
            } else if draftMode == .block {
                controller.startBlocking()
            }
        } label: {
            HStack(spacing: 9) {
                if controller.isBusy { ProgressView() }
                Text(draftMode == .dailyLimit ? "Apply daily limit" : "Block selected apps")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(accentInk)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canApply)
        .accessibilityIdentifier("focus-apply")
    }

    private var statusTitle: String {
        if isSimulator { return "Screen Time preview" }
        if !controller.hasReadableConfiguration { return "Restriction status unavailable" }
        if !controller.isAuthorized && controller.configuration.mode != .off { return "Saved restriction" }
        if !controller.isAuthorized { return "Screen Time isn’t connected" }
        if !controller.sharedStorageAvailable { return "Screen Time setup needed" }
        if controller.configuration.mode == .block { return "Blocking is on" }
        if controller.configuration.mode == .dailyLimit {
            return controller.isDailyLimitReached ? "Today’s limit is reached" : "Daily limit is on"
        }
        return "Your apps are unrestricted"
    }

    private var statusDetail: String {
        if isSimulator { return "You can review this screen here. App restrictions aren’t enforced in the simulator." }
        if !controller.hasReadableConfiguration { return "Saved restrictions could not be verified. They may still be applied. Use Turn off restrictions or revoke Screen Time access in Settings to recover." }
        if !controller.isAuthorized && controller.configuration.mode != .off { return "Reconnect Screen Time to verify and manage this saved boundary; it may still be applied." }
        if !controller.isAuthorized { return "Connect below to set a boundary for your own iPhone." }
        if !controller.sharedStorageAvailable { return "Your saved restrictions can’t be verified in this build. Complete the app’s Screen Time setup before applying a boundary." }
        if controller.configuration.mode == .block { return "Your saved selection stays blocked until you turn restrictions off." }
        if controller.configuration.mode == .dailyLimit {
            return controller.isDailyLimitReached
                ? "The saved selection is blocked for the rest of today. Access returns with the next daily interval."
                : "A combined budget of \(shortMinutes(controller.configuration.dailyMinutes)) applies to your saved selection each day."
        }
        return "Choose apps and apply a boundary when you’re ready."
    }

    private var statusSymbol: String {
        if isSimulator { return "iphone" }
        if !controller.isAuthorized && controller.configuration.mode != .off { return "shield" }
        if !controller.isAuthorized { return "hand.raised" }
        return controller.configuration.mode == .off ? "lock.open" : "shield.lefthalf.filled"
    }

    private func shortMinutes(_ value: Int) -> String {
        if value < 60 { return "\(value) min" }
        let hours = value / 60, remainder = value % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private func notice(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(border))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(border, lineWidth: 1))
    }
}
#endif
