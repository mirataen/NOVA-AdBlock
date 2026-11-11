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

    var enabled: Bool { status == .connected || status == .connecting || status == .reasserting }

    var statusLabel: String {
        switch status {
        case .connected: return "Protection active"
        case .connecting, .reasserting: return "Connecting"
        case .disconnecting: return "Disconnecting"
        default: return "Protection off"
        }
    }

    func updateStatus() {
        status = manager?.connection.status ?? .disconnected
    }

    func reload() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier ==
                    "com.nova.adblock.tunnel"
            })
            updateStatus()
        } catch {
            errorText = "Unable to read VPN settings: \(error.localizedDescription)"
        }
    }

    func setProtection(_ turnOn: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        errorText = nil
        do {
            if turnOn {
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                let mgr = managers.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier ==
                        "com.nova.adblock.tunnel"
                }) ?? NETunnelProviderManager()
                let protocolConfig = NETunnelProviderProtocol()
                protocolConfig.providerBundleIdentifier = "com.nova.adblock.tunnel"
                protocolConfig.serverAddress = "On-device DNS"
                protocolConfig.providerConfiguration = ["configVersion": 1]
                mgr.localizedDescription = "NOVA AdBlock"
                mgr.protocolConfiguration = protocolConfig
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
            errorText = "Could not change protection: \(error.localizedDescription). Check that both app and tunnel extension are signed with the required Network Extension entitlement."
            await reload()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var vpn: VPNController

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.11).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 78, weight: .light))
                        .foregroundStyle(.cyan)
                        .padding(.top, 45)
                    Text("NOVA AdBlock")
                        .font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("Private, local DNS protection")
                        .foregroundStyle(.white.opacity(0.67))
                    VStack(spacing: 16) {
                        HStack {
                            Circle().fill(vpn.enabled ? Color.green : Color.gray)
                                .frame(width: 12, height: 12)
                            Text(vpn.statusLabel).font(.title3.bold())
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        Toggle("Enable protection", isOn: Binding(
                            get: { vpn.enabled },
                            set: { value in Task { await vpn.setProtection(value) } }
                        ))
                        .tint(.cyan)
                        .disabled(vpn.busy)
                    }
                    .padding(22)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 14) {
                        Label("OISD Big", systemImage: "checkmark.shield")
                        Label("Wi-Fi + Cellular DNS", systemImage: "wifi")
                        Label("On-device domain decisions", systemImage: "iphone")
                        Label("DNS-over-HTTPS upstream for allowed queries", systemImage: "lock.shield")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(20)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                    Text("Blocks domains, not in-page cosmetic elements. Some apps use their own encrypted DNS. A VPN configuration is required, but web traffic does not route through a remote VPN server.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.55))
                    if let error = vpn.errorText {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
    }
}
