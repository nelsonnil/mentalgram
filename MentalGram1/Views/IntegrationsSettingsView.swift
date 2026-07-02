import SwiftUI

struct IntegrationsSettingsView: View {
    @ObservedObject private var settings = IntegrationsSettings.shared
    @State private var testingSource: ApiSource? = nil
    @State private var testingExploreSpy = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Explore Spy
                sectionLabel("EXPLORE SPY", icon: "magnifyingglass.circle.fill")
                card {
                    cardHeader(icon: "magnifyingglass.circle.fill", iconColor: .purple,
                               title: "Explore Spy")

                    Text("When enabled, any profile the spectator views in the Explore search is automatically sent to Inject 2.0.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)

                    divider()

                    // Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send profile data")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text("Fires silently when a profile loads")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.exploreSpyEnabled)
                            .labelsHidden()
                            .tint(VaultTheme.Colors.primary)
                    }

                    divider()

                    // Inject 2.0 ID
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inject 2.0 ID (gg0.us)")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        TextField("e.g. 5136", text: $settings.exploreSpy2InjectId)
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .padding(10)
                            .background(Color(hex: "#2C2C2E"))
                            .cornerRadius(8)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.numberPad)
                    }

                    divider()

                    // Format picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data format")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        ForEach(ExploreSpyFormat.allCases, id: \.rawValue) { fmt in
                            Button {
                                settings.exploreSpyFormat = fmt
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: settings.exploreSpyFormat == fmt
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(settings.exploreSpyFormat == fmt
                                                         ? VaultTheme.Colors.primary : .gray)
                                        .font(.system(size: 16))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(fmt.displayName)
                                            .font(VaultTheme.Typography.body())
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                                        Text(fmt.example)
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    divider()

                    // Test button
                    exploreSpyTestButton
                }

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
                    cardHeader(icon: "link", iconColor: .cyan,
                               title: LocalizedStringKey(settings.customApi1Name.isEmpty ? "Custom API 1" : settings.customApi1Name))
                    nameField(name: $settings.customApi1Name, placeholder: "Custom API 1")
                    customApiFields(url: $settings.customApi1Url,
                                    field: $settings.customApi1Field,
                                    source: .custom1)
                }
                card {
                    cardHeader(icon: "link", iconColor: .teal,
                               title: LocalizedStringKey(settings.customApi2Name.isEmpty ? "Custom API 2" : settings.customApi2Name))
                    nameField(name: $settings.customApi2Name, placeholder: "Custom API 2")
                    customApiFields(url: $settings.customApi2Url,
                                    field: $settings.customApi2Field,
                                    source: .custom2)
                }
                card {
                    cardHeader(icon: "link", iconColor: .mint,
                               title: LocalizedStringKey(settings.customApi3Name.isEmpty ? "Custom API 3" : settings.customApi3Name))
                    nameField(name: $settings.customApi3Name, placeholder: "Custom API 3")
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

    // MARK: - Explore Spy Test Button

    @ViewBuilder
    private var exploreSpyTestButton: some View {
        Button {
            guard !testingExploreSpy else { return }
            testingExploreSpy = true
            Task {
                let id = settings.exploreSpy2InjectId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else {
                    await MainActor.run {
                        testingExploreSpy = false
                        alertTitle = "Missing ID"
                        alertMessage = "Enter your Inject 2.0 ID (gg0.us) above first."
                        showingAlert = true
                    }
                    return
                }
                let testValue: String
                switch settings.exploreSpyFormat {
                case .followersOnly:          testValue = "12 345"
                case .followersFollowing:     testValue = "12 345, 678"
                case .nameFollowers:          testValue = "Test User, 12 345"
                case .nameFollowersFollowing: testValue = "Test User, 12 345, 678"
                }
                let ok = await IntegrationsSettings.shared.sendToInject2(id: id, value: testValue)
                await MainActor.run {
                    testingExploreSpy = false
                    alertTitle = ok ? "✅ Connected" : "❌ Failed"
                    alertMessage = ok
                        ? "Sent \"\(testValue)\" to Inject 2.0 successfully."
                        : "Could not reach gg0.us. Check your ID and internet connection."
                    showingAlert = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                if testingExploreSpy {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(testingExploreSpy ? "integrations.testing" : "Test Send")
                    .font(VaultTheme.Typography.bodyBold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.purple)
            .cornerRadius(8)
        }
        .disabled(testingExploreSpy)
    }

    // MARK: - Name Field

    @ViewBuilder
    private func nameField(name: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name (shown in pickers)")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
            TextField(placeholder, text: name)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .padding(10)
                .background(Color(hex: "#2C2C2E"))
                .cornerRadius(8)
                .autocorrectionDisabled()
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
