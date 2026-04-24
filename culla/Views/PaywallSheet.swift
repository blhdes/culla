import SwiftUI
import RevenueCat

struct PaywallSheet: View {
    let onClose: () -> Void
    var dismissible: Bool = true

    @Environment(\.appAccent) private var accent
    @Environment(SubscriptionManager.self) private var subscriptions

    @State private var offering: Offering?
    @State private var selectedPackage: Package?
    @State private var eligibility: [String: IntroEligibilityStatus] = [:]
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).ignoresSafeArea())

            if dismissible {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        .task { await loadOfferings() }
        .alert("Purchase failed", isPresented: Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        ), presenting: purchaseError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let error = loadError {
            errorView(message: error)
        } else if let offering, !offering.availablePackages.isEmpty {
            paywallBody(offering: offering)
        } else {
            errorView(message: "No subscription options are available right now. Please try again later.")
        }
    }

    // MARK: - Loading & Error States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await loadOfferings() }
            } label: {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Paywall Body

    private func paywallBody(offering: Offering) -> some View {
        ScrollView {
            VStack(spacing: 32) {
                hero

                features

                VStack(spacing: 12) {
                    ForEach(offering.availablePackages, id: \.identifier) { package in
                        packageCard(package)
                    }
                }
                .padding(.horizontal, 16)

                VStack(spacing: 12) {
                    ctaButton
                    if let package = selectedPackage, introductoryTrialDays(package) != nil {
                        trialDisclosure(for: package)
                    }
                    footerLinks
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 56)
            .padding(.bottom, 32)
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("culla Pro")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(1.5)

            Text("Sort smarter. Keep what matters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "infinity", title: "Unlimited sorting", detail: "No daily limits on your photo library")
            featureRow(icon: "sparkles", title: "Duplicate sweep", detail: "Find and remove duplicate photos instantly")
            featureRow(icon: "chart.bar.fill", title: "Insights & streaks", detail: "Track your cleanup progress over time")
            featureRow(icon: "paintpalette.fill", title: "Custom accents", detail: "Personalise colours and backgrounds")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Package Card

    private func packageCard(_ package: Package) -> some View {
        let isSelected = selectedPackage?.identifier == package.identifier
        return Button {
            selectedPackage = package
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? accent : Color.secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(packageTitle(package))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle = packageSubtitle(package) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let perUnit = pricePerUnit(package) {
                        Text(perUnit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - CTA & Footer

    private var ctaButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            ZStack {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(ctaTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(accent, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isPurchasing || isRestoring || selectedPackage == nil)
        .opacity(selectedPackage == nil ? 0.6 : 1)
    }

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        if let trialDays = introductoryTrialDays(package) {
            return "Start \(trialDays)-day free trial"
        }
        return "Continue"
    }

    private func trialDisclosure(for package: Package) -> some View {
        let priceSuffix = pricePerUnit(package).map { " \($0)" } ?? ""
        return Text("Free for 7 days, then \(package.storeProduct.localizedPriceString)\(priceSuffix). Cancel anytime in Settings before the trial ends — you won't be charged if you cancel in time.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
    }

    private var footerLinks: some View {
        HStack(spacing: 16) {
            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Restore")
                        .font(.caption.weight(.semibold))
                }
            }
            .disabled(isPurchasing || isRestoring)

            Text("·")
                .foregroundStyle(.secondary)

            Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                .font(.caption.weight(.semibold))

            Text("·")
                .foregroundStyle(.secondary)

            Link("Privacy", destination: URL(string: "https://www.revenuecat.com/privacy")!)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Data

    private func loadOfferings() async {
        isLoading = true
        loadError = nil
        do {
            let offerings = try await Purchases.shared.offerings()
            let current = offerings.current
            await MainActor.run {
                offering = current
                selectedPackage = defaultPackage(for: current)
                isLoading = false
            }
            await fetchEligibility(for: current)
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func fetchEligibility(for offering: Offering?) async {
        guard let offering else { return }
        let ids = offering.availablePackages.map { $0.storeProduct.productIdentifier }
        guard !ids.isEmpty else { return }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: ids)
        let map = result.mapValues { $0.status }
        await MainActor.run { eligibility = map }
    }

    private func defaultPackage(for offering: Offering?) -> Package? {
        guard let offering else { return nil }
        return offering.annual
            ?? offering.availablePackages.first(where: { $0.packageType == .annual })
            ?? offering.availablePackages.first
    }

    @MainActor
    private func purchase() async {
        guard let package = selectedPackage, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return }
            if result.customerInfo.entitlements[SubscriptionManager.entitlementID]?.isActive == true {
                onClose()
            }
        } catch {
            // RevenueCat returns a cancelled flag rather than throwing for user cancels,
            // so anything that lands here is a real failure worth showing.
            purchaseError = error.localizedDescription
        }
    }

    @MainActor
    private func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await subscriptions.restorePurchases()
            if subscriptions.isPro {
                onClose()
            } else {
                purchaseError = "No active subscription found on this account."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Package formatting

    private func packageTitle(_ package: Package) -> String {
        switch package.packageType {
        case .lifetime: return "Lifetime"
        case .annual: return "Yearly"
        case .sixMonth: return "6 Months"
        case .threeMonth: return "3 Months"
        case .twoMonth: return "2 Months"
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        default: return package.storeProduct.localizedTitle
        }
    }

    private func packageSubtitle(_ package: Package) -> String? {
        if let days = introductoryTrialDays(package) {
            return "\(days)-day free trial"
        }
        return nil
    }

    private func pricePerUnit(_ package: Package) -> String? {
        guard let period = package.storeProduct.subscriptionPeriod else { return nil }
        switch period.unit {
        case .year: return "per year"
        case .month where period.value == 1: return "per month"
        case .month: return "per \(period.value) months"
        case .week: return "per week"
        case .day: return "per day"
        default: return nil
        }
    }

    private func introductoryTrialDays(_ package: Package) -> Int? {
        // Hide the trial only when we're *sure* the user is ineligible.
        // `.unknown` or missing status → show the trial optimistically.
        if eligibility[package.storeProduct.productIdentifier] == .ineligible { return nil }
        guard
            let intro = package.storeProduct.introductoryDiscount,
            intro.paymentMode == .freeTrial
        else { return nil }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }
}
