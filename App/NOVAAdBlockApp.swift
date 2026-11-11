import SwiftUI
import NetworkExtension

@main
struct NOVAAdBlockApp: App {
    @StateObject private var vpn = VPNController()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(vpn)
        }
    }
}

enum ProtectionMode: String, CaseIterable, Identifiable {
    case dns = "DNS only"
    case vpnFiltering = "VPN + AdBlock"
    case vpn = "VPN only"
    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .dns: return "Filter domains locally without changing your public IP"
        case .vpnFiltering: return "Requires a remote VPN server and VPN protocol"
        case .vpn: return "Requires a remote VPN server and VPN protocol"
        }
    }
    var symbol: String {
        switch self {
        case .dns: return "shield.lefthalf.filled"
        case .vpnFiltering: return "lock.shield"
        case .vpn: return "network"
        }
    }
}

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var busy = false
    @Published var errorText: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatus() }
        }
        Task { await reload() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var enabled: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    var statusLabel: String {
        switch status {
        case .connected: return "Local DNS protection active"
        case .connecting, .reasserting: return "Connecting"
        case .disconnecting: return "Disconnecting"
        default: return "Disconnected"
        }
    }

    func updateStatus() {
        status = manager?.connection.status ?? .disconnected
    }

    func reload() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                    == "com.nova.adblock.tunnel"
            }
            updateStatus()
        } catch {
            errorText = "Unable to read VPN settings: \(error.localizedDescription)"
        }
    }

    func setProtection(_ enabled: Bool, resolver: String,
                       filtering: Bool, allowed: [String], blocked: [String]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        errorText = nil
        do {
            if enabled {
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                let mgr = managers.first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                        == "com.nova.adblock.tunnel"
                } ?? NETunnelProviderManager()

                let config = NETunnelProviderProtocol()
                config.providerBundleIdentifier = "com.nova.adblock.tunnel"
                config.serverAddress = "On-device DNS"
                config.providerConfiguration = [
                    "configVersion": "2",
                    "dnsResolver": resolver,
                    "filterEnabled": filtering ? "1" : "0",
                    "allowDomains": allowed,
                    "blockDomains": blocked
                ]
                mgr.localizedDescription = "NOVA AdBlock DNS"
                mgr.protocolConfiguration = config
                mgr.isEnabled = true
                try await mgr.saveToPreferences()
                try await mgr.loadFromPreferences()
                manager = mgr
                try mgr.connection.startVPNTunnel()
            } else {
                manager?.connection.stopVPNTunnel()
            }
            updateStatus()
        } catch {
            errorText = "Cannot change protection: \(error.localizedDescription). The app and extension must be signed with matching Network Extension capabilities."
            await reload()
        }
    }
}

private func parseDomainLines(_ text: String) -> [String] {
    let items = text.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == " " || $0 == "\t" })
    return Array(Set(items.map {
        String($0).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }.filter { candidate in
        !candidate.isEmpty &&
        candidate.count <= 253 &&
        candidate.contains(".") &&
        candidate.utf8.allSatisfy {
            (97...122).contains(Int($0)) || (48...57).contains(Int($0)) || $0 == 45 || $0 == 46
        }
    })).sorted()
}

struct ContentView: View {
    @EnvironmentObject private var vpn: VPNController
    @AppStorage("nova.resolver") private var resolver = "cloudflare"
    @AppStorage("nova.filterEnabled") private var filterEnabled = true
    @AppStorage("nova.allowDomains") private var allowDomains = ""
    @AppStorage("nova.blockDomains") private var blockDomains = ""
    @State private var selectedMode: ProtectionMode = .dns

    private var changesRequireReconnect: String {
        "DNS settings and custom rules apply when you next connect."
    }

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.11).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    status
                    modeChooser
                    if selectedMode == .dns {
                        dnsSettings
                    } else {
                        vpnSetup
                    }
                    Text("Designed for iOS 27. Actual tunnel activation requires Apple Network Extension entitlements in both signing profiles. No traffic is sent to an undisclosed VPN server.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.cyan)
                .frame(width: 72, height: 72)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 5) {
                Text("NOVA AdBlock")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("PRIVACY • NETWORK • CONTROL")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(.cyan)
            }
            Spacer()
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(vpn.enabled ? Color.green : Color.gray)
                    .frame(width: 11, height: 11)
                Text(vpn.statusLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.cyan)
            }
            if selectedMode == .dns {
                Button {
                    Task {
                        await vpn.setProtection(!vpn.enabled,
                                                resolver: resolver,
                                                filtering: filterEnabled,
                                                allowed: parseDomainLines(allowDomains),
                                                blocked: parseDomainLines(blockDomains))
                    }
                } label: {
                    Label(vpn.enabled ? "Disconnect DNS" : "Connect DNS protection",
                          systemImage: vpn.enabled ? "stop.fill" : "power")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                }
                .buttonStyle(.plain)
                .background(vpn.enabled ? Color.white.opacity(0.16) : Color.cyan,
                            in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(vpn.enabled ? .white : .black)
                .disabled(vpn.busy)
            } else {
                Text("Remote VPN is not configured. No VPN traffic is being routed by this mode.")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
            }
            if let error = vpn.errorText {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(20)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 22))
    }

    private var modeChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protection mode")
                .font(.title3.bold())
                .foregroundStyle(.white)
            ForEach(ProtectionMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: mode.symbol)
                            .font(.title3)
                            .frame(width: 32)
                            .foregroundStyle(mode == selectedMode ? .cyan : .white.opacity(0.75))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.rawValue)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(mode.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer(minLength: 4)
                        Image(systemName: mode == selectedMode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(mode == selectedMode ? .cyan : .white.opacity(0.5))
                    }
                    .padding(15)
                    .background(.white.opacity(mode == selectedMode ? 0.13 : 0.05),
                                in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dnsSettings: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("DNS & filter settings")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Toggle(isOn: $filterEnabled) {
                VStack(alignment: .leading) {
                    Text("OISD Big filtering").font(.headline)
                    Text("Local domain matching").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
            }
            .tint(.cyan)

            Picker("Encrypted DNS upstream", selection: $resolver) {
                Text("Cloudflare DoH").tag("cloudflare")
                Text("Quad9 DoH").tag("quad9")
            }
            .tint(.cyan)

            Text("Allowlisted domains")
                .font(.subheadline.bold())
            TextEditor(text: $allowDomains)
                .scrollContentBackground(.hidden)
                .frame(height: 86)
                .padding(7)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("Extra blocked domains")
                .font(.subheadline.bold())
            TextEditor(text: $blockDomains)
                .scrollContentBackground(.hidden)
                .frame(height: 86)
                .padding(7)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("Enter one domain per line. Allowlist rules override OISD Big and custom blocks. " + changesRequireReconnect)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.63))
            Text("Supported today: IPv4/UDP DNS with DNS-over-HTTPS forwarding. DNS-over-TLS and IPv6 are planned, not active.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.63))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
    }

    private var vpnSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Remote VPN setup required", systemImage: "server.rack")
                .font(.headline)
                .foregroundStyle(.yellow)
            Text("The local DNS tunnel cannot forward all internet traffic to a remote VPN. This mode needs a VPN server, approved connection profile, and an actual packet encryption/transport implementation (such as WireGuardKit).")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
            Text("Do not enter private VPN keys in a public GitHub repository. VPN mode remains unavailable until configured and verified.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20))
    }
}
