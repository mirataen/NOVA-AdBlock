import Foundation
import NetworkExtension
import Darwin

/// On-device DNS proxy. Only the virtual DNS IP is routed into the tunnel.
/// Normal app data remains on the Wi-Fi / cellular interface.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let dnsAddress = "198.18.0.1"
    private var blocklist: DomainBlocklist?
    private var active = false
    private lazy var upstream: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        do {
            guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "txt") else {
                throw NSError(domain: "NOVA", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "OISD Big blocklist missing from tunnel bundle"])
            }
            blocklist = try DomainBlocklist(url: url)
        } catch {
            completionHandler(error)
            return
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: dnsAddress)
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.2"],
                                  subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: dnsAddress,
                        subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: [dnsAddress])
        dns.matchDomains = [""]
        dns.matchDomainsNoSearch = true
        settings.dnsSettings = dns
        settings.mtu = 1500

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(NSError(domain: "NOVA", code: 2))
                return
            }
            if error == nil {
                self.active = true
                self.readLoop()
            }
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        active = false
        upstream.invalidateAndCancel()
        blocklist = nil
        completionHandler()
    }

    private func readLoop() {
        guard active else { return }
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, self.active else { return }
            for packet in packets {
                self.handle(packet)
            }
            self.readLoop()
        }
    }

    private func handle(_ packet: Data) {
        guard let query = DNSPacket(packet: packet), query.destinationPort == 53 else {
            return
        }
        if blocklist?.blocks(query.domain) == true {
            reply(query: query, dns: DNSPacket.errorAnswer(to: query.dns, code: 3))
            return
        }

        // IP-literal HTTPS endpoint avoids resolving the upstream name via
        // the virtual DNS address and causing a DNS bootstrap loop.
        guard let url = URL(string: "https://1.1.1.1/dns-query") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(query.dns)
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        upstream.dataTask(with: request) { [weak self] data, response, _ in
            guard let self, self.active else { return }
            let http = response as? HTTPURLResponse
            let answer: [UInt8]
            if http?.statusCode == 200, let data,
               data.count >= 12, data.count <= 4096 {
                answer = Array(data)
            } else {
                answer = DNSPacket.errorAnswer(to: query.dns, code: 2)
            }
            self.reply(query: query, dns: answer)
        }.resume()
    }

    private func reply(query: DNSPacket, dns: [UInt8]) {
        guard active, let response = query.makeIPv4UDPResponse(dns: dns) else {
            return
        }
        packetFlow.writePackets([response], withProtocols: [NSNumber(value: AF_INET)])
    }
}

private struct DNSPacket {
    let sourceIP: [UInt8]
    let destinationIP: [UInt8]
    let sourcePort: UInt16
    let destinationPort: UInt16
    let dns: [UInt8]
    let domain: String

    init?(packet: Data) {
        let bytes = [UInt8](packet)
        guard bytes.count >= 40, bytes[0] >> 4 == 4 else { return }
        let ipLength = Int(bytes[0] & 0x0f) * 4
        guard ipLength >= 20, bytes.count >= ipLength + 8 + 12,
              bytes[9] == 17,
              (UInt16(bytes[6]) << 8 | UInt16(bytes[7])) & 0x1fff == 0
        else { return }
        let totalLength = Int(bytes[2]) << 8 | Int(bytes[3])
        guard totalLength <= bytes.count, totalLength >= ipLength + 20 else { return }

        let udpOffset = ipLength
        let udpLength = Int(bytes[udpOffset + 4]) << 8 | Int(bytes[udpOffset + 5])
        guard udpLength >= 20, udpOffset + udpLength <= totalLength else { return }
        sourceIP = Array(bytes[12..<16])
        destinationIP = Array(bytes[16..<20])
        sourcePort = UInt16(bytes[udpOffset]) << 8 | UInt16(bytes[udpOffset+1])
        destinationPort = UInt16(bytes[udpOffset+2]) << 8 | UInt16(bytes[udpOffset+3])
        dns = Array(bytes[(udpOffset + 8)..<(udpOffset + udpLength)])
        guard dns.count >= 17, dns[2] & 0x80 == 0,
              dns[4] == 0, dns[5] == 1,
              let parsed = DNSPacket.readQuestionDomain(dns)
        else { return }
        domain = parsed
    }

    private static func readQuestionDomain(_ message: [UInt8]) -> String? {
        var position = 12
        var labels: [String] = []
        while position < message.count {
            let length = Int(message[position])
            position += 1
            if length == 0 {
                guard position + 4 <= message.count else { return nil }
                return labels.joined(separator: ".").lowercased()
            }
            guard length <= 63, labels.count < 128, position + length <= message.count else {
                return nil
            }
            let label = Array(message[position..<(position + length)])
            guard let string = String(bytes: label, encoding: .ascii) else { return nil }
            labels.append(string)
            position += length
        }
        return nil
    }

    static func errorAnswer(to message: [UInt8], code: UInt8) -> [UInt8] {
        guard message.count >= 12 else { return [] }
        var offset = 12
        while offset < message.count {
            let len = Int(message[offset])
            offset += 1
            if len == 0 { break }
            guard len <= 63, offset + len <= message.count else { return [] }
            offset += len
        }
        guard offset + 4 <= message.count else { return [] }
        var response = Array(message[0..<(offset + 4)])
        response[2] = 0x81
        response[3] = 0x80 | code // NXDOMAIN=3, SERVFAIL=2
        for index in 6..<12 { response[index] = 0 }
        return response
    }

    func makeIPv4UDPResponse(dns answer: [UInt8]) -> Data? {
        let udpLength = answer.count + 8
        let ipLength = udpLength + 20
        guard !answer.isEmpty, ipLength <= 65535 else { return nil }

        var bytes = [UInt8](repeating: 0, count: ipLength)
        bytes[0] = 0x45
        bytes[2] = UInt8(ipLength >> 8)
        bytes[3] = UInt8(ipLength & 0xff)
        bytes[6] = 0x40 // Don't fragment
        bytes[8] = 64
        bytes[9] = 17 // UDP
        bytes.replaceSubrange(12..<16, with: destinationIP)
        bytes.replaceSubrange(16..<20, with: sourceIP)
        let checksum = DNSPacket.ipv4Checksum(bytes[0..<20])
        bytes[10] = UInt8(checksum >> 8)
        bytes[11] = UInt8(checksum & 0xff)

        bytes[20] = UInt8(destinationPort >> 8)
        bytes[21] = UInt8(destinationPort & 0xff)
        bytes[22] = UInt8(sourcePort >> 8)
        bytes[23] = UInt8(sourcePort & 0xff)
        bytes[24] = UInt8(udpLength >> 8)
        bytes[25] = UInt8(udpLength & 0xff)
        // IPv4 permits a zero UDP checksum.
        bytes.replaceSubrange(28..<ipLength, with: answer)
        return Data(bytes)
    }

    private static func ipv4Checksum(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        let values = Array(bytes)
        var sum: UInt32 = 0
        for index in stride(from: 0, to: values.count, by: 2) {
            sum += UInt32(values[index]) << 8 | UInt32(values[index + 1])
        }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }
}

/// Memory-mapped, sorted OISD domain list: binary search without allocating
/// a large in-memory Set. Match exact domain and parent-domain suffixes.
private final class DomainBlocklist {
    private let contents: Data

    init(url: URL) throws {
        contents = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !contents.isEmpty else {
            throw NSError(domain: "NOVA", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Empty OISD blocklist"])
        }
    }

    func blocks(_ domain: String) -> Bool {
        var candidate = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        while !candidate.isEmpty {
            if contains(candidate) { return true }
            guard let dot = candidate.firstIndex(of: ".") else { return false }
            candidate = String(candidate[candidate.index(after: dot)...])
        }
        return false
    }

    private func contains(_ domain: String) -> Bool {
        let needle = Array(domain.utf8)
        return contents.withUnsafeBytes { raw in
            let data = raw.bindMemory(to: UInt8.self)
            var lo = 0
            var hi = data.count
            while lo < hi {
                let midpoint = lo + (hi - lo) / 2
                var first = midpoint
                while first > 0 && data[first - 1] != 10 { first -= 1 }
                var last = first
                while last < data.count && data[last] != 10 { last += 1 }

                var matched = 0
                while matched < needle.count && first + matched < last &&
                      data[first + matched] == needle[matched] {
                    matched += 1
                }
                if matched == needle.count && first + matched == last { return true }

                let rowBeforeNeedle: Bool
                if first + matched == last {
                    rowBeforeNeedle = true
                } else if matched == needle.count {
                    rowBeforeNeedle = false
                } else {
                    rowBeforeNeedle = data[first + matched] < needle[matched]
                }
                if rowBeforeNeedle {
                    lo = last + 1
                } else {
                    hi = first
                }
            }
            return false
        }
    }
}
