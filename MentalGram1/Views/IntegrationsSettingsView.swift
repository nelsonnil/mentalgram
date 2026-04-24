import SwiftUI

struct IntegrationsSettingsView: View {
    @ObservedObject private var settings = IntegrationsSettings.shared
    @State private var testingSource: ApiSource? = nil
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Inject
                sectionLabel("INJECT (11z.co)", icon: "bolt.fill")
                card {
                    cardHeader(icon: "bolt.fill", iconColor: .yellow, title: "Inject")
                    Text("Fetches a word/text from 11z.co using your Inject ID.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                    divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("integrations.inject_id")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        TextField("e.g. abc123", text: $settings.injectID)
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .padding(10)
                            .background(Color(hex: "#2C2C2E"))
                            .cornerRadius(8)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    testButton(source: .inject)
                }

                // MARK: - Custom APIs
                sectionLabel("CUSTOM APIs", icon: "link")
                card {
                    cardHeader(icon: "link", iconColor: .cyan, title: "Custom API 1")
                    customApiFields(url: $settings.customApi1Url,
                                    field: $settings.customApi1Field,
                                    source: .custom1)
                }
                card {
                    cardHeader(icon: "link", iconColor: .teal, title: "Custom API 2")
                    customApiFields(url: $settings.customApi2Url,
                                    field: $settings.customApi2Field,
                                    source: .custom2)
                }
                card {
                    cardHeader(icon: "link", iconColor: .mint, title: "Custom API 3")
                    customApiFields(url: $settings.customApi3Url,
                                    field: $settings.customApi3Field,
                                    source: .custom3)
                }

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(Color(hex: "#0F0F0F").ignoresSafeArea())
        .navigationTitle("Integrations")
        .toolbarBackground(Color(hex: "#1C1C1E"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Custom API Fields

    @ViewBuilder
    private func customApiFields(url: Binding<String>, field: Binding<String>, source: ApiSource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("URL")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
            TextField("https://api.example.com/word", text: url)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .padding(10)
                .background(Color(hex: "#2C2C2E"))
                .cornerRadius(8)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("integrations.json_field")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
            TextField("e.g. word", text: field)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .padding(10)
                .background(Color(hex: "#2C2C2E"))
                .cornerRadius(8)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
        testButton(source: source)
    }

    // MARK: - Test Button

    @ViewBuilder
    private func testButton(source: ApiSource) -> some View {
        let isLoading = testingSource == source
        Button {
            testingSource = source
            Task {
                let value = await settings.fetchValue(for: source)
                await MainActor.run {
                    testingSource = nil
                    if let v = value, !v.isEmpty {
                        alertTitle = String(localized: "integrations.connection_ok")
                        alertMessage = String(localized: "integrations.response_received") + "\n\"\(v)\""
                    } else {
                        alertTitle = String(localized: "integrations.no_response")
                        alertMessage = source == .inject
                            ? String(localized: "integrations.check_inject_id")
                            : String(localized: "integrations.check_url_field")
                    }
                    showingAlert = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(isLoading ? "integrations.testing" : "integrations.test_connection")
                    .font(VaultTheme.Typography.bodyBold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(VaultTheme.Colors.primary)
            .cornerRadius(8)
        }
        .disabled(testingSource != nil)
    }

    // MARK: - UI Helpers

    @ViewBuilder
    private func sectionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(VaultTheme.Colors.textSecondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .tracking(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(14)
            .background(Color(hex: "#1C1C1E"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#2C2C2E"), lineWidth: 0.5))
    }

    @ViewBuilder
    private func cardHeader(icon: String, iconColor: Color, title: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(iconColor.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(iconColor)
            }
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(VaultTheme.Colors.textPrimary)
        }
    }

    private func divider() -> some View {
        Divider().background(Color(hex: "#2C2C2E"))
    }
}
