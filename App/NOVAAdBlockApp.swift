import SwiftUI

@main
struct NOVAAdBlockApp: App {
    var body: some Scene {
        WindowGroup {
            NOVAHomeView()
        }
    }
}

/// An entitlement-free companion to encrypted DNS configuration profiles.
/// The app does NOT claim to configure iOS DNS by itself.
private enum DNSProvider: String, CaseIterable, Identifiable {
    case big = "OISD Big"
    case alternative = "OISD Full alternative"

    var id: String { rawValue }

    var service: String {
        switch self {
        case .big: return "Public RDNS Lite"
        case .alternative: return "Control D Free DNS"
        }
    }

    var endpoint: String {
        switch self {
        case .big: return "https://lite.public-rdns.com/dns-query"
        case .alternative: return "https://freedns.controld.com/x-oisd"
        }
    }

    var profileName: String {
        switch self {
        case .big: return "NOVA-OISD-Big.mobileconfig"
        case .alternative: return "NOVA-OISD-Full-Alternative.mobileconfig"
        }
    }

    var details: String {
        switch self {
        case .big:
            return "Uses the OISD Big list advertised by Public RDNS Lite."
        case .alternative:
            return "Uses Control D's free OISD Full DNS preset."
        }
    }

    var providerInfoURL: URL {
        let address: String
        switch self {
        case .big: address = "https://public-rdns.com/lite.html"
        case .alternative: address = "https://controld.com/free-dns/"
        }
        return URL(string: address)!
    }

    var profileURL: URL {
        URL(string: "https://raw.githubusercontent.com/mirataen/NOVA-AdBlock/main/profiles/" + profileName)!
    }
}

struct NOVAHomeView: View {
    @AppStorage("nova.profileChoice") private var selectedProvider = "OISD Big"
    @State private var confirmedInstalled = false

    private var choice: DNSProvider {
        DNSProvider(rawValue: selectedProvider) ?? .big
    }

    private let navy = Color(red: 0.035, green: 0.055, blue: 0.11)
    private let cyan = Color(red: 0.18, green: 0.82, blue: 0.98)

    var body: some View {
        ZStack {
            navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    profileStatus
                    providerSelector
                    installSection
                    informationSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 15) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(cyan)
                .frame(width: 78, height: 78)
                .background(cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 21))
            VStack(alignment: .leading, spacing: 6) {
                Text("NOVA AdBlock")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("DNS PROFILE EDITION")
                    .font(.caption.weight(.bold))
                    .tracking(1.7)
                    .foregroundStyle(cyan)
            }
            Spacer()
        }
    }

    private var profileStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No VPN permission required", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("This version has no VPN or Network Extension. iOS applies the encrypted DNS configuration after you install a profile in Settings.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text("DNS status cannot be automatically verified by this companion app.")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.68))

            Toggle("I installed and selected the DNS profile", isOn: $confirmedInstalled)
                .tint(cyan)
                .foregroundStyle(.white)

            Text(confirmedInstalled ? "Marked installed by you — not independently verified" : "Installation not yet confirmed")
                .font(.caption)
                .foregroundStyle(confirmedInstalled ? .green : .orange)
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private var providerSelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your filter")
                .font(.title3.bold())
                .foregroundStyle(.white)

            ForEach(DNSProvider.allCases) { provider in
                Button {
                    selectedProvider = provider.rawValue
                    confirmedInstalled = false
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.title2)
                            .foregroundStyle(cyan)
                            .frame(width: 35)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.rawValue).font(.headline)
                            Text(provider.service).font(.caption).foregroundStyle(.white.opacity(0.66))
                            Text(provider.details).font(.caption).foregroundStyle(.white.opacity(0.56))
                        }
                        Spacer(minLength: 3)
                        Image(systemName: choice == provider ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(choice == provider ? cyan : .gray)
                    }
                    .foregroundStyle(.white)
                    .padding(15)
                    .background(.white.opacity(choice == provider ? 0.14 : 0.055),
                                in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
            }

            Text("Your DNS queries go to the selected third-party provider. NOVA does not host the resolver or process DNS requests itself.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Install DNS protection")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Link(destination: choice.profileURL) {
                Label("Download DNS profile in Safari", systemImage: "arrow.down.doc.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .foregroundStyle(.black)
                    .background(cyan, in: RoundedRectangle(cornerRadius: 16))
            }

            Link(destination: choice.providerInfoURL) {
                Label("Provider details and alternative download", systemImage: "safari.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 11) {
                step("1", "Open the profile link using Safari on your iPhone.")
                step("2", "Allow the profile download if iOS prompts you.")
                step("3", "Go to Settings → General → VPN & Device Management.")
                step("4", "Choose the downloaded profile, review its DNS endpoint, then tap Install.")
                step("5", "Select it in iOS DNS settings if prompted; remove other DNS profiles to prevent conflicts.")
            }

            Text("Profile endpoint: " + choice.endpoint)
                .font(.footnote.monospaced())
                .foregroundStyle(cyan)
                .textSelection(.enabled)

            Text("iOS 27 deprecates the older manually installed DNS profile payload. Availability may vary; test the profile in Settings. If installation fails, use the provider's official profile instructions or managed DNS settings.")
                .font(.footnote)
                .foregroundStyle(.yellow)
        }
        .padding(18)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
    }

    private func step(_ number: String, _ explanation: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 23, height: 23)
                .background(cyan, in: Circle())
            Text(explanation).font(.subheadline).foregroundStyle(.white.opacity(0.9))
        }
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What this edition does", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)

            Text("The DNS profile can cover Wi-Fi and cellular. It is not a remote VPN, does not change your public IP, and does not eliminate in-page cosmetic ads or traffic from apps using their own encrypted DNS.")
            Text("A VPN, private relay, or other DNS configuration may override the profile. To turn off DNS protection, remove or disable the profile in iOS Settings.")
            Text("OISD Big rules are maintained by the selected DNS provider. The old local blocklist, custom domain rules and VPN controls are not included in this edition.")
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.69))
        .padding(.bottom, 24)
    }
}
