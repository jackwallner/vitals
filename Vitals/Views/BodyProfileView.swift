import SwiftUI

/// Settings → Body Profile. Free BMI from Apple Health or manual height/weight,
/// with a Vitals+ upsell for body-fat and calorie context. The BMI number is
/// never paywalled — it's the product/ASO promise (see 625plan.md §6).
struct BodyProfileView: View {
    @EnvironmentObject private var store: StoreService
    @StateObject private var bodyProfile = BodyProfileStore.shared

    @State private var health: HealthBodyProfile = .empty
    @State private var healthStatusMessage: String?
    @State private var isSyncing = false

    // Manual entry text drafts (seeded from store, committed on change).
    @State private var feetText = ""
    @State private var inchesText = ""
    @State private var poundsText = ""
    @State private var cmText = ""
    @State private var kgText = ""
    @State private var bodyFatText = ""

    /// The Vitals+ pitch, presented right here. Body Profile is pushed inside
    /// the Settings sheet, so handing the tap to MainTabView meant asking it to
    /// present a sheet over a sheet — which SwiftUI drops silently.
    @State private var trialPitch: TrialPitchRequest?

    @State private var heightError = false
    @State private var weightError = false
    @State private var bodyFatError = false

    private var unitSystem: BodyProfileUnitSystem { bodyProfile.effectiveUnitSystem }

    private var resolved: ResolvedBodyProfile {
        bodyProfile.resolved(health: health)
    }

    /// Apple Health is the active source and has a complete height+weight pair.
    private var usingAppleHealthData: Bool {
        bodyProfile.preferredSource == .appleHealth && health.hasHeightAndWeight
    }

    /// Manual fields only when the user chose manual, or Health is preferred but
    /// incomplete so we need a fallback entry path.
    private var showsManualEntry: Bool {
        bodyProfile.preferredSource == .manual
            || (bodyProfile.preferredSource == .appleHealth && !health.hasHeightAndWeight)
    }

    private var manualEntryTitle: String {
        bodyProfile.preferredSource == .manual ? "Manual Entry" : "Enter Height & Weight"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                bmiCard
                sourceCard
                if showsManualEntry {
                    manualEntryCard
                }
                educationCard
                vitalsPlusCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Body Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $trialPitch) { pitch in
            TrialOfferPitchSheet(request: pitch, onDismiss: { trialPitch = nil })
                .environmentObject(store)
        }
        .task {
            seedManualDrafts()
            // Settled-auth silent read: populates from Health when already
            // authorized, without prompting. The user explicitly syncs otherwise.
            health = (try? await HealthKitService.shared.fetchBodyProfileFromHealth(includeBodyFat: store.isPro)) ?? .empty
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.netDeficitBrand.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.stand")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.netDeficitBrand)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Body Profile")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(headerSubtitle)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var headerSubtitle: String {
        if usingAppleHealthData {
            return "BMI from height and weight synced from Apple Health."
        }
        if bodyProfile.preferredSource == .manual {
            return "BMI from height and weight you enter."
        }
        return "Sync from Apple Health or enter height and weight below."
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usingAppleHealthData {
                HStack(spacing: 10) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.caloriesPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Height and weight sync automatically.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button("Sync") {
                        Task { await syncFromHealth() }
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .disabled(isSyncing)
                }

                if isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Syncing…")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                displayUnitsRow

                Button("Enter height and weight manually") {
                    switchToManual(seedingFromHealth: true)
                }
                .font(.system(.caption, design: .rounded, weight: .medium))
            } else if bodyProfile.preferredSource == .manual {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual Entry")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("You're entering height and weight yourself.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Button {
                    switchToAppleHealth()
                } label: {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "heart.text.square.fill")
                        }
                        Text(isSyncing ? "Syncing…" : "Use Apple Health Instead")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.caloriesGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
            } else {
                Text("Connect Apple Health")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Vitals can read height and weight you've logged in Apple Health.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await syncFromHealth() }
                } label: {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "heart.text.square.fill")
                        }
                        Text(isSyncing ? "Syncing…" : "Sync from Apple Health")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.caloriesGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
            }

            if let healthStatusMessage {
                Text(healthStatusMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var displayUnitsRow: some View {
        HStack {
            Text("Display units")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("Units", selection: Binding(
                get: { bodyProfile.unitSystem },
                set: { bodyProfile.unitSystem = $0; seedManualDrafts() }
            )) {
                ForEach(BodyProfileUnitSystem.allCases, id: \.self) { system in
                    Text(system.label).tag(system)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.caloriesPrimary)
        }
    }

    // MARK: - BMI

    private var bmiCard: some View {
        VStack(spacing: 12) {
            Text("Body Mass Index")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(BodyProfileCalculator.formattedBMI(resolved.bmi))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())

            if let category = resolved.category {
                Text(category.label)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(categoryColor(category))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(categoryColor(category).opacity(0.15), in: Capsule())
            } else {
                Text("Add height and weight to see your BMI.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }

            if resolved.heightMeters != nil || resolved.weightKilograms != nil {
                Divider().background(Theme.textTertiary.opacity(0.2))
                HStack {
                    metricColumn(label: "Height", value: heightDisplay)
                    Spacer()
                    metricColumn(label: "Weight", value: weightDisplay)
                    Spacer()
                    metricColumn(label: "Source", value: resolved.source.label)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bmiAccessibilityLabel)
    }

    private func metricColumn(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func categoryColor(_ category: BMICategory) -> Color {
        switch category {
        case .underweight: Theme.stepsSecondary
        case .healthy: Theme.streakPrimary
        case .overweight: Theme.caloriesSecondary
        case .obesity: Theme.caloriesPrimary
        }
    }

    // MARK: - Manual entry

    private var manualEntryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(manualEntryTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("Units", selection: Binding(
                    get: { bodyProfile.unitSystem },
                    set: { bodyProfile.unitSystem = $0; seedManualDrafts() }
                )) {
                    ForEach(BodyProfileUnitSystem.allCases, id: \.self) { system in
                        Text(system.label).tag(system)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.caloriesPrimary)
            }

            if bodyProfile.preferredSource == .appleHealth && !health.hasHeightAndWeight {
                Text("Apple Health doesn't have height and weight yet. Enter them here or add them in the Health app.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if unitSystem == .us {
                HStack(spacing: 10) {
                    entryField(title: "Feet", text: $feetText, unit: "ft")
                    entryField(title: "Inches", text: $inchesText, unit: "in")
                }
                if heightError {
                    fieldError("Enter a realistic height.")
                }
                entryField(title: "Weight", text: $poundsText, unit: "lb")
                if weightError {
                    fieldError("Enter a realistic weight.")
                }
            } else {
                entryField(title: "Height", text: $cmText, unit: "cm")
                if heightError {
                    fieldError("Enter a realistic height.")
                }
                entryField(title: "Weight", text: $kgText, unit: "kg")
                if weightError {
                    fieldError("Enter a realistic weight.")
                }
            }

            if store.isPro {
                entryField(title: "Body Fat", text: $bodyFatText, unit: "%")
                if bodyFatError {
                    fieldError("Enter a body fat between 2% and 75%.")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func entryField(title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: 90)
                .onChange(of: text.wrappedValue) { _, _ in commitManualEntry() }
            Text(unit)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 28, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func fieldError(_ message: String) -> some View {
        Text(message)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.red)
    }

    // MARK: - Education

    private var educationCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textTertiary)
            Text("BMI is a simple height/weight reference and is not a diagnosis. It may not reflect muscle mass, pregnancy, age, or individual health context.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Vitals+

    @ViewBuilder
    private var vitalsPlusCard: some View {
        if store.isPro {
            proBodyContextCard
        } else {
            lockedBodyContextRow
        }
    }

    private var proBodyContextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Your calorie context")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack {
                Text("Body Fat")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(BodyProfileCalculator.formattedBodyFat(resolved.bodyFatPercent))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            if resolved.bodyFatPercent == nil {
                Text("Add body fat in Apple Health or switch to manual entry to include it here.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().background(Theme.textTertiary.opacity(0.2))

            Text("TDEE and BMR estimate your burn. BMI and body fat help frame your body profile.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var lockedBodyContextRow: some View {
        Button {
            trialPitch = TrialPitchRequest(
                intent: .bodyProfileDetails,
                impressionID: "vitals_trial_offer_settings"
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.netDeficitBrand.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.netDeficitBrand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body fat and calorie context are in Vitals+.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your BMI stays free.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock body fat and calorie context with Vitals+. Your BMI stays free.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Display helpers

    private var heightDisplay: String {
        guard let meters = resolved.heightMeters else { return "—" }
        if unitSystem == .us {
            let (feet, inches) = BodyProfileCalculator.feetInches(fromMeters: meters)
            return "\(feet)′\(inches)″"
        }
        return String(format: "%.0f cm", BodyProfileCalculator.centimeters(fromMeters: meters))
    }

    private var weightDisplay: String {
        guard let kg = resolved.weightKilograms else { return "—" }
        if unitSystem == .us {
            return String(format: "%.0f lb", BodyProfileCalculator.pounds(fromKilograms: kg))
        }
        return String(format: "%.1f kg", kg)
    }

    private var bmiAccessibilityLabel: String {
        var parts = ["Body Mass Index"]
        if let bmi = resolved.bmi {
            parts.append(BodyProfileCalculator.formattedBMI(bmi))
            if let category = resolved.category { parts.append(category.label) }
            parts.append("Source \(resolved.source.label)")
            parts.append("Height \(heightDisplay)")
            parts.append("Weight \(weightDisplay)")
        } else {
            parts.append("Not enough data. Add height and weight.")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Data flow

    private func switchToManual(seedingFromHealth: Bool) {
        if seedingFromHealth {
            if let meters = health.heightMeters { bodyProfile.setManualHeight(meters: meters) }
            if let kg = health.weightKilograms { bodyProfile.setManualWeight(kilograms: kg) }
            if let pct = health.bodyFatPercent { bodyProfile.setManualBodyFat(percent: pct) }
        }
        bodyProfile.preferredSource = .manual
        healthStatusMessage = nil
        seedManualDrafts()
    }

    private func switchToAppleHealth() {
        bodyProfile.preferredSource = .appleHealth
        healthStatusMessage = nil
        Task { await syncFromHealth() }
    }

    private func syncFromHealth() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await HealthKitService.shared.requestBodyProfileAuthorization(includeBodyFat: store.isPro)
            let fetched = try await HealthKitService.shared.fetchBodyProfileFromHealth(includeBodyFat: store.isPro)
            health = fetched
            if fetched.hasHeightAndWeight {
                bodyProfile.preferredSource = .appleHealth
                healthStatusMessage = nil
            } else {
                healthStatusMessage = "Couldn’t find height and weight in Apple Health. You can enter them manually here."
            }
        } catch {
            healthStatusMessage = "Couldn’t read from Apple Health. Enter your height and weight manually here."
        }
    }

    /// Parse the current text drafts, validate, and write metric values to the
    /// store. Invalid fields flip an inline error and are not persisted.
    private func commitManualEntry() {
        // Height
        if unitSystem == .us {
            let feet = BodyProfileCalculator.parseDecimal(feetText) ?? 0
            let inches = BodyProfileCalculator.parseDecimal(inchesText) ?? 0
            if feetText.isEmpty && inchesText.isEmpty {
                bodyProfile.setManualHeight(meters: nil)
                heightError = false
            } else {
                let meters = BodyProfileCalculator.meters(feet: feet, inches: inches)
                heightError = !bodyProfile.setManualHeight(meters: meters)
            }
            if poundsText.isEmpty {
                bodyProfile.setManualWeight(kilograms: nil)
                weightError = false
            } else if let pounds = BodyProfileCalculator.parseDecimal(poundsText) {
                let kg = BodyProfileCalculator.kilograms(pounds: pounds)
                weightError = !bodyProfile.setManualWeight(kilograms: kg)
            } else {
                weightError = true
            }
        } else {
            if cmText.isEmpty {
                bodyProfile.setManualHeight(meters: nil)
                heightError = false
            } else if let cm = BodyProfileCalculator.parseDecimal(cmText) {
                let meters = BodyProfileCalculator.meters(centimeters: cm)
                heightError = !bodyProfile.setManualHeight(meters: meters)
            } else {
                heightError = true
            }
            if kgText.isEmpty {
                bodyProfile.setManualWeight(kilograms: nil)
                weightError = false
            } else if let kg = BodyProfileCalculator.parseDecimal(kgText) {
                weightError = !bodyProfile.setManualWeight(kilograms: kg)
            } else {
                weightError = true
            }
        }

        // Body fat (Pro only)
        if store.isPro {
            if bodyFatText.isEmpty {
                bodyProfile.setManualBodyFat(percent: nil)
                bodyFatError = false
            } else if let pct = BodyProfileCalculator.parseDecimal(bodyFatText) {
                bodyFatError = !bodyProfile.setManualBodyFat(percent: pct)
            } else {
                bodyFatError = true
            }
        }
    }

    private func seedManualDrafts() {
        if let meters = bodyProfile.manualHeightMeters {
            let (feet, inches) = BodyProfileCalculator.feetInches(fromMeters: meters)
            feetText = String(feet)
            inchesText = String(inches)
            cmText = String(format: "%.0f", BodyProfileCalculator.centimeters(fromMeters: meters))
        } else {
            feetText = ""
            inchesText = ""
            cmText = ""
        }
        if let kg = bodyProfile.manualWeightKilograms {
            poundsText = String(format: "%.0f", BodyProfileCalculator.pounds(fromKilograms: kg))
            kgText = String(format: "%.1f", kg)
        } else {
            poundsText = ""
            kgText = ""
        }
        if let pct = bodyProfile.manualBodyFatPercent {
            bodyFatText = String(format: "%.1f", pct)
        } else {
            bodyFatText = ""
        }
    }
}
