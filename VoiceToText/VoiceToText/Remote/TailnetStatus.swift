import Foundation

/// The part of an embedded Tailscale node's status (Go's `ipnstate.Status`,
/// as `TailscaleNode.statusJSON()` returns it) that both apps read: the
/// backend state, the sign-in URL, and who owns this node and each peer.
///
/// Decoded here rather than through TailscaleKit's `IpnState.Status`, whose
/// peer type has no `UserID`; the owner is what `RemoteAccessPolicy` checks.
/// Every field is optional on the wire so a status from a newer Tailscale
/// still decodes. Foundation-only, so the harness tests it with fixtures.
nonisolated struct TailnetStatus: Decodable, Equatable, Sendable {
    struct Node: Decodable, Equatable, Sendable, Identifiable {
        /// The stable node id: survives renames and address changes, so the
        /// phone remembers its Mac by it.
        let id: String
        let hostName: String
        let dnsName: String
        let addresses: [String]
        let userID: Int64?
        let isOnline: Bool
        let tags: [String]

        enum CodingKeys: String, CodingKey {
            case id = "ID", hostName = "HostName", dnsName = "DNSName"
            case addresses = "TailscaleIPs", userID = "UserID", isOnline = "Online", tags = "Tags"
        }

        init(id: String, hostName: String, dnsName: String, addresses: [String], userID: Int64?, isOnline: Bool, tags: [String]) {
            self.id = id
            self.hostName = hostName
            self.dnsName = dnsName
            self.addresses = addresses
            self.userID = userID
            self.isOnline = isOnline
            self.tags = tags
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            hostName = try c.decodeIfPresent(String.self, forKey: .hostName) ?? ""
            dnsName = try c.decodeIfPresent(String.self, forKey: .dnsName) ?? ""
            addresses = try c.decodeIfPresent([String].self, forKey: .addresses) ?? []
            userID = try c.decodeIfPresent(Int64.self, forKey: .userID)
            isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
            tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        }

        /// The machine name as the admin console shows it ("voicetotext-mac-studio"
        /// from "voicetotext-mac-studio.tail1234.ts.net."), or the host name the
        /// node asked for when it has none yet.
        var machineName: String {
            let first = dnsName.split(separator: ".").first.map(String.init) ?? ""
            return first.isEmpty ? hostName : first
        }

        /// An IPv4 address when there is one: it is what the phone dials.
        var preferredAddress: String? {
            addresses.first { $0.contains(".") } ?? addresses.first
        }
    }

    struct User: Decodable, Equatable, Sendable {
        let id: Int64
        let loginName: String
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case id = "ID", loginName = "LoginName", displayName = "DisplayName"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
            loginName = try c.decodeIfPresent(String.self, forKey: .loginName) ?? ""
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        }
    }

    private struct Tailnet: Decodable, Equatable, Sendable {
        let name: String?
        enum CodingKeys: String, CodingKey { case name = "Name" }
    }

    let backendState: String
    let authURL: String
    let selfNode: Node?
    let peers: [Node]
    let users: [Int64: User]
    let tailnetName: String?

    enum CodingKeys: String, CodingKey {
        case backendState = "BackendState", authURL = "AuthURL", selfNode = "Self"
        case peers = "Peer", users = "User", tailnet = "CurrentTailnet"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backendState = try c.decodeIfPresent(String.self, forKey: .backendState) ?? ""
        authURL = try c.decodeIfPresent(String.self, forKey: .authURL) ?? ""
        selfNode = try c.decodeIfPresent(Node.self, forKey: .selfNode)
        let peerMap = try c.decodeIfPresent([String: Node].self, forKey: .peers) ?? [:]
        peers = peerMap.values.sorted { $0.id < $1.id }
        let userMap = try c.decodeIfPresent([String: User].self, forKey: .users) ?? [:]
        var users: [Int64: User] = [:]
        for user in userMap.values { users[user.id] = user }
        self.users = users
        tailnetName = try c.decodeIfPresent(Tailnet.self, forKey: .tailnet)?.name
    }

    static func decode(_ data: Data) throws -> TailnetStatus {
        try JSONDecoder().decode(TailnetStatus.self, from: data)
    }

    /// The signed-in account's login ("name@example.com"), else the tailnet's
    /// name, for "Signed in as …".
    var accountName: String? {
        if let id = selfNode?.userID, let user = users[id] {
            if !user.loginName.isEmpty { return user.loginName }
            if !user.displayName.isEmpty { return user.displayName }
        }
        return tailnetName.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The peer that holds `address` ("100.64.0.7", "[fd7a:115c:a1e0::7]",
    /// either with or without a port).
    func peer(withAddress address: String) -> Node? {
        guard let ip = Self.normalizedIP(address) else { return nil }
        return peers.first { node in node.addresses.contains { Self.normalizedIP($0) == ip } }
    }

    /// VoiceToText Macs signed in to this node's own account, online ones
    /// first, then by name.
    var ownMacs: [Node] {
        peers
            .filter { RemoteHostName.isMac($0.hostName) && RemoteAccessPolicy.sameOwner($0, as: self) }
            .sorted { lhs, rhs in
                if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
                return lhs.machineName.localizedStandardCompare(rhs.machineName) == .orderedAscending
            }
    }

    /// "100.64.0.7" from any of the forms the tailnet reports a caller in.
    static func normalizedIP(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            text = String(text[text.index(after: text.startIndex)..<close])
        } else if text.filter({ $0 == ":" }).count == 1 {
            text = String(text.split(separator: ":")[0])
        }
        if let zone = text.firstIndex(of: "%") { text = String(text[..<zone]) }
        return text.isEmpty ? nil : text.lowercased()
    }
}

/// Who may use the Mac's remote API. Being on the tailnet is not enough: a
/// tailnet can hold other people's devices (a team's tailnet, a node shared
/// in from someone else, a device shared out to them). Only a caller whose
/// node belongs to the same Tailscale user as this Mac's node is served.
nonisolated enum RemoteAccessPolicy {
    enum Decision: Equatable, Sendable {
        case allow(TailnetStatus.Node)
        case deny(String)
    }

    static func decide(remoteAddress: String, status: TailnetStatus) -> Decision {
        guard status.backendState == "Running", let me = status.selfNode else {
            return .deny("this Mac isn't connected to Tailscale")
        }
        guard let owner = me.userID, owner != 0 else {
            return .deny("this Mac's node has no owner")
        }
        // A tagged node belongs to its tags, not to a person, and every tagged
        // node reports the same placeholder owner, so a tagged Mac would
        // accept every tagged device on the tailnet as "the same user".
        guard me.tags.isEmpty else {
            return .deny("this Mac's node is tagged")
        }
        guard let peer = status.peer(withAddress: remoteAddress) else {
            return .deny("\(remoteAddress) isn't a known peer")
        }
        guard sameOwner(peer, as: status) else {
            return .deny("\(peer.machineName) belongs to another user")
        }
        return .allow(peer)
    }

    static func sameOwner(_ peer: TailnetStatus.Node, as status: TailnetStatus) -> Bool {
        guard let me = status.selfNode, let owner = me.userID, owner != 0,
              me.tags.isEmpty, peer.tags.isEmpty else { return false }
        return peer.userID == owner
    }
}

/// What the Tailscale settings show, derived from the node's backend state
/// and whether the user has asked to sign in. Pure, so the harness covers
/// the mapping.
nonisolated enum TailnetState: Equatable, Sendable {
    /// The node isn't running: the feature is off, or the phone is in the
    /// background.
    case off
    case starting
    /// Running, but with no account; the user hasn't asked to sign in.
    case signedOut
    /// The user asked to sign in and this is the page to finish it on.
    case needsLogin(URL)
    /// Signing in, or reconnecting with an account it already has.
    case connecting
    case running(account: String)
    case failed(String)

    static func derive(
        backendState: String,
        authURL: String,
        browseURL: URL?,
        loginRequested: Bool,
        accountName: String?
    ) -> TailnetState {
        switch backendState {
        case "Running":
            return .running(account: accountName ?? "Tailscale")
        case "NeedsLogin", "Stopped":
            guard loginRequested else { return .signedOut }
            if let url = browseURL ?? URL(string: authURL), !authURL.isEmpty || browseURL != nil {
                return .needsLogin(url)
            }
            return .connecting
        case "NeedsMachineAuth":
            return .failed("This device is waiting for approval in the Tailscale admin console.")
        case "InUseOtherUser":
            return .failed("Tailscale is in use by another user on this device.")
        default:
            return loginRequested ? .connecting : .starting
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
