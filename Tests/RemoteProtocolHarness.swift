import Foundation

struct RemoteProtocolHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RemoteProtocolHarnessFailure(description: message)
    }
}

@main
struct RemoteProtocolHarness {
    static func main() throws {
        try statusRoundTrips()
        try conversationListKeepsOnlyConversationsNewestFirst()
        try rowPreviewAndFlags()
        try entryRoundTripsThroughTheWireCoders()
        try parsesRequests()
        try parsesRequestsSplitAcrossReads()
        try refusesMalformedRequests()
        try framesResponses()
        try matchesRoutes()
        try sanitisesHostNames()
        try decodesTailnetStatus()
        try allowsOnlyTheSameUser()
        try derivesTailnetState()
        print("Remote protocol harness passed")
    }

    // MARK: - DTOs

    private static func statusRoundTrips() throws {
        let status = RemoteStatus(state: .recording, elapsed: 12.5, message: nil, mac: "Studio", appVersion: "0.4.0", protocol: 1)
        let data = try RemoteProtocol.makeEncoder().encode(status)
        let back = try RemoteProtocol.makeDecoder().decode(RemoteStatus.self, from: data)
        try expect(back == status, "status round-trips")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try expect(object?["state"] as? String == "recording", "state is a plain string on the wire")
        try expect(object?["protocol"] as? Int == 1, "protocol field is named protocol")
        try expect(object?["elapsed"] as? Double == 12.5, "elapsed is seconds")

        let error = RemoteStatus(state: .error, elapsed: 0, message: "Microphone access is required.", mac: "Studio", appVersion: "0.4.0", protocol: 1)
        let errorBack = try RemoteProtocol.makeDecoder().decode(RemoteStatus.self, from: RemoteProtocol.makeEncoder().encode(error))
        try expect(errorBack.message == "Microphone access is required.", "error text survives")
    }

    private static func entry(
        _ id: UUID = UUID(),
        at seconds: TimeInterval,
        transcript: String = "Hello there.",
        source: RecordingHistoryEntry.Source? = .meeting,
        summary: TranscriptSummary? = nil,
        actionItems: TranscriptActionItems? = nil,
        status: RecordingHistoryEntry.Status? = nil
    ) -> RecordingHistoryEntry {
        RecordingHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: seconds),
            transcript: transcript,
            audioFileName: "\(id.uuidString).wav",
            durationSeconds: 61.5,
            sampleRate: 16000,
            modelId: "parakeet",
            modelName: "Parakeet TDT v3",
            source: source,
            summary: summary,
            actionItems: actionItems,
            status: status
        )
    }

    private static func conversationListKeepsOnlyConversationsNewestFirst() throws {
        let older = entry(at: 1_000)
        let newer = entry(at: 2_000)
        let dictation = entry(at: 3_000, source: .dictation)
        let legacyDictation = entry(at: 4_000, source: nil)
        let list = RemoteConversationList.make(from: [older, dictation, newer, legacyDictation])
        try expect(list.conversations.map(\.id) == [newer.id, older.id], "only conversations, newest first")

        let data = try RemoteProtocol.makeEncoder().encode(list)
        let back = try RemoteProtocol.makeDecoder().decode(RemoteConversationList.self, from: data)
        try expect(back == list, "the list round-trips")
        try expect(back.conversations[0].createdAt == newer.createdAt, "dates survive exactly")
    }

    private static func rowPreviewAndFlags() throws {
        let long = String(repeating: "word ", count: 100)
        let row = RemoteConversationRow(entry: entry(at: 0, transcript: "  Line one\n\nline   two  "))
        try expect(row.preview == "Line one line two", "whitespace collapses")
        let longRow = RemoteConversationRow(entry: entry(at: 0, transcript: long))
        try expect(longRow.preview.hasSuffix("…"), "a long preview is cut with an ellipsis")
        try expect(longRow.preview.count <= RemoteConversationRow.previewLength + 1, "the preview is short")

        let summary = TranscriptSummary(text: "Summary", generatedAt: Date(), modelId: nil, sourceDigest: "x")
        let none = TranscriptActionItems(items: [], generatedAt: Date(), modelId: nil, sourceDigest: "x")
        let some = TranscriptActionItems(
            items: [ActionItem(id: UUID(), text: "Send notes", owner: nil, due: nil, isDone: false)],
            generatedAt: Date(), modelId: nil, sourceDigest: "x"
        )
        let flagged = RemoteConversationRow(entry: entry(at: 0, summary: summary, actionItems: some))
        try expect(flagged.hasSummary && flagged.hasActionItems, "summary and action items are flagged")
        let empty = RemoteConversationRow(entry: entry(at: 0, actionItems: none))
        try expect(!empty.hasActionItems, "an empty checklist isn't flagged")

        let failed = RemoteConversationRow(entry: entry(
            at: 0,
            transcript: RecordingHistoryEntry.placeholderTranscript,
            status: .init(kind: .failed, message: "No key")
        ))
        try expect(failed.isUntranscribed && failed.preview.isEmpty, "an untranscribed row has no preview")
        let legacy = RemoteConversationRow(entry: entry(at: 0, transcript: RecordingHistoryEntry.legacyRecoveredTranscript))
        try expect(legacy.isUntranscribed, "an older build's placeholder is untranscribed too")
        try expect(row.modelName == "Parakeet TDT v3", "the model name is carried")
    }

    private static func entryRoundTripsThroughTheWireCoders() throws {
        let summary = TranscriptSummary(text: "## Points\n- One", generatedAt: Date(timeIntervalSince1970: 5.25), modelId: "gpt", sourceDigest: "d")
        let original = entry(at: 1_234.5, transcript: "Speaker 1: hi", summary: summary)
        let data = try RemoteProtocol.makeEncoder().encode(original)
        let back = try RemoteProtocol.makeDecoder().decode(RecordingHistoryEntry.self, from: data)
        try expect(back == original, "a full entry round-trips")
    }

    // MARK: - HTTP

    private static func parsesRequests() throws {
        let raw = Data("GET /v1/status?x=1 HTTP/1.1\r\nHost: 100.64.0.1:47610\r\nAccept: */*\r\nX-Twice: a\r\nx-twice: b\r\n\r\n".utf8)
        guard case .complete(let request) = RemoteHTTPParser.parse(raw) else {
            throw RemoteProtocolHarnessFailure(description: "a GET parses")
        }
        try expect(request.method == "GET", "method")
        try expect(request.path == "/v1/status", "path without the query")
        try expect(request.query == "x=1", "query kept separately")
        try expect(request.headers["host"] == "100.64.0.1:47610", "header names are lowercased")
        try expect(request.headers["x-twice"] == "b", "a repeated header keeps its last value")
        try expect(request.body.isEmpty, "no body")

        let post = Data("POST /v1/conversation/start HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}".utf8)
        guard case .complete(let started) = RemoteHTTPParser.parse(post) else {
            throw RemoteProtocolHarnessFailure(description: "a POST with a body parses")
        }
        try expect(started.body == Data("{}".utf8), "the body is read by Content-Length")

        let empty = Data("POST /v1/conversation/stop HTTP/1.1\r\nContent-Length: 0\r\n\r\n".utf8)
        guard case .complete = RemoteHTTPParser.parse(empty) else {
            throw RemoteProtocolHarnessFailure(description: "an empty POST parses")
        }
        let oldClient = Data("GET / HTTP/1.0\r\n\r\n".utf8)
        guard case .complete = RemoteHTTPParser.parse(oldClient) else {
            throw RemoteProtocolHarnessFailure(description: "HTTP/1.0 parses")
        }
    }

    private static func parsesRequestsSplitAcrossReads() throws {
        let full = Data("POST /v1/conversation/start HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello".utf8)
        for cut in 1..<full.count {
            let outcome = RemoteHTTPParser.parse(full.prefix(cut))
            try expect(outcome == .incomplete, "a prefix of \(cut) bytes is incomplete")
        }
        guard case .complete(let request) = RemoteHTTPParser.parse(full) else {
            throw RemoteProtocolHarnessFailure(description: "the whole request parses")
        }
        try expect(request.body == Data("hello".utf8), "the body is complete")
    }

    private static func status(_ raw: String) -> Int? {
        if case .invalid(let status, _) = RemoteHTTPParser.parse(Data(raw.utf8)) { return status }
        return nil
    }

    private static func refusesMalformedRequests() throws {
        try expect(status("GET /v1/status\r\n\r\n") == 400, "a request line without a version")
        try expect(status("GET  /v1/status HTTP/1.1\r\n\r\n") == 400, "a doubled space")
        try expect(status("get /v1/status HTTP/1.1\r\n\r\n") == 400, "a lowercase method")
        try expect(status("GET http://x/v1/status HTTP/1.1\r\n\r\n") == 400, "an absolute target")
        try expect(status("GET /v1/status HTTP/2\r\n\r\n") == 505, "an unsupported version")
        try expect(status("GET /v1/status HTTP/1.1\r\nBad Header: x\r\n\r\n") == 400, "a space in a header name")
        try expect(status("GET /v1/status HTTP/1.1\r\nNoColon\r\n\r\n") == 400, "a header without a colon")
        try expect(status("GET /v1/status HTTP/1.1\r\nA: b\r\n folded\r\n\r\n") == 400, "an obsolete folded header")
        try expect(status("POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n") == 400, "a negative length")
        try expect(status("POST /x HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab") == 400, "conflicting lengths")
        try expect(status("POST /x HTTP/1.1\r\nContent-Length: 999999\r\n\r\n") == 413, "a body over the limit")
        try expect(status("POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") == 501, "chunked bodies")

        let huge = Data(("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: RemoteHTTPParser.maxHeaderBytes + 1)).utf8)
        guard case .invalid(431, _) = RemoteHTTPParser.parse(huge) else {
            throw RemoteProtocolHarnessFailure(description: "endless headers are refused before they end")
        }
    }

    private static func framesResponses() throws {
        let response = RemoteHTTPResponse.json(RemoteErrorBody(error: "nope"), status: 403)
        let head = String(decoding: response.head(), as: UTF8.self)
        try expect(head.hasPrefix("HTTP/1.1 403 Forbidden\r\n"), "status line")
        try expect(head.contains("Content-Type: application/json\r\n"), "content type")
        guard case .data(let body) = response.body else {
            throw RemoteProtocolHarnessFailure(description: "a JSON reply carries data")
        }
        try expect(head.contains("Content-Length: \(body.count)\r\n"), "content length matches the body")
        try expect(head.contains("Connection: close\r\n"), "one request per connection")
        try expect(head.hasSuffix("\r\n\r\n"), "the head ends with a blank line")
        let decoded = try RemoteProtocol.makeDecoder().decode(RemoteErrorBody.self, from: body)
        try expect(decoded.error == "nope", "the error body decodes")

        let file = RemoteHTTPResponse(status: 200, contentType: "audio/mp4", body: .file(URL(fileURLWithPath: "/x.m4a"), length: 123_456_789))
        try expect(String(decoding: file.head(), as: UTF8.self).contains("Content-Length: 123456789\r\n"), "a file's length is announced up front")
        try expect(RemoteHTTPResponse.reason(for: 404) == "Not Found", "reason phrases")
    }

    private static func matchesRoutes() throws {
        let id = UUID()
        try expect(RemoteRoute.match(method: "GET", path: "/v1/status") == .success(.status), "status")
        try expect(RemoteRoute.match(method: "POST", path: "/v1/conversation/start") == .success(.startConversation), "start")
        try expect(RemoteRoute.match(method: "POST", path: "/v1/conversation/stop") == .success(.stopConversation), "stop")
        try expect(RemoteRoute.match(method: "GET", path: "/v1/conversations") == .success(.conversations), "list")
        try expect(RemoteRoute.match(method: "GET", path: RemoteProtocol.Path.conversation(id)) == .success(.conversation(id)), "detail")
        try expect(RemoteRoute.match(method: "GET", path: RemoteProtocol.Path.audio(id)) == .success(.audio(id)), "audio")
        try expect(RemoteRoute.match(method: "GET", path: "/v1/conversations/\(id.uuidString.lowercased())") == .success(.conversation(id)), "a lowercase id")
        try expect(RemoteRoute.match(method: "GET", path: "/v1/conversation/start") == .failure(.methodNotAllowed), "start is POST only")
        try expect(RemoteRoute.match(method: "POST", path: "/v1/status") == .failure(.methodNotAllowed), "status is GET only")
        try expect(RemoteRoute.match(method: "DELETE", path: RemoteProtocol.Path.conversation(id)) == .failure(.methodNotAllowed), "nothing deletes")
        try expect(RemoteRoute.match(method: "GET", path: "/v1/conversations/not-a-uuid") == .failure(.notFound), "a bad id")
        try expect(RemoteRoute.match(method: "GET", path: "/v1/conversations/\(id.uuidString)/transcript") == .failure(.notFound), "an unknown sub-path")
        try expect(RemoteRoute.match(method: "GET", path: "/v1/conversations/\(id.uuidString)/audio/x") == .failure(.notFound), "a deeper path")
        try expect(RemoteRoute.match(method: "GET", path: "/") == .failure(.notFound), "the root")
        try expect(RemoteRoute.match(method: "GET", path: "/v1/conversations/../status") == .failure(.notFound), "no path tricks")
    }

    private static func sanitisesHostNames() throws {
        try expect(RemoteHostName.mac(computerName: "Gurgen’s MacBook Pro") == "voicetotext-mac-gurgens-macbook-pro", "apostrophes vanish, spaces become hyphens")
        try expect(RemoteHostName.mac(computerName: "Mac  Studio (2)") == "voicetotext-mac-mac-studio-2", "runs of punctuation collapse")
        try expect(RemoteHostName.mac(computerName: "Café Ünïcode") == "voicetotext-mac-cafe-unicode", "accents fold")
        try expect(RemoteHostName.mac(computerName: "Компьютер") == "voicetotext-mac-komp-uter", "other scripts are transliterated")
        try expect(RemoteHostName.mac(computerName: "!!!") == "voicetotext-mac", "nothing usable falls back to the prefix")
        try expect(RemoteHostName.mac(computerName: "") == "voicetotext-mac", "an empty name")
        let long = RemoteHostName.mac(computerName: String(repeating: "abcdef ", count: 20))
        try expect(long.count <= RemoteHostName.maxLength, "fits in a DNS label")
        try expect(!long.hasSuffix("-"), "never ends in a hyphen")
        try expect(RemoteHostName.phone(deviceName: "iPhone") == "voicetotext-iphone", "a generic device name adds nothing")
        try expect(RemoteHostName.phone(deviceName: "Ann's iPhone 16") == "voicetotext-iphone-anns-iphone-16", "a real device name is kept")
        try expect(RemoteHostName.isMac("voicetotext-mac-studio"), "a Mac")
        try expect(RemoteHostName.isMac("VoiceToText-Mac"), "case doesn't matter")
        try expect(!RemoteHostName.isMac("voicetotext-macbook"), "a prefix without its hyphen isn't one")
        try expect(!RemoteHostName.isMac("voicetotext-iphone"), "a phone isn't a Mac")
    }

    // MARK: - Tailnet

    static let fixture = #"""
    {
      "Version": "1.104.1",
      "BackendState": "Running",
      "AuthURL": "",
      "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
      "Self": {"ID": "nSelf", "HostName": "voicetotext-mac-studio", "DNSName": "voicetotext-mac-studio.tail1.ts.net.",
               "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"], "UserID": 11, "Online": true, "NewFieldFromTheFuture": 3},
      "CurrentTailnet": {"Name": "ann@example.com", "MagicDNSSuffix": "tail1.ts.net", "MagicDNSEnabled": true},
      "Peer": {
        "nodekey:phone": {"ID": "nPhone", "HostName": "voicetotext-iphone", "DNSName": "voicetotext-iphone.tail1.ts.net.",
                          "TailscaleIPs": ["100.64.0.2", "fd7a:115c:a1e0::2"], "UserID": 11, "Online": true},
        "nodekey:other": {"ID": "nOther", "HostName": "bobs-phone", "DNSName": "bobs-phone.tail1.ts.net.",
                          "TailscaleIPs": ["100.64.0.3"], "UserID": 22, "Online": true},
        "nodekey:tagged": {"ID": "nTagged", "HostName": "server", "DNSName": "server.tail1.ts.net.",
                           "TailscaleIPs": ["100.64.0.4"], "UserID": 11, "Online": true, "Tags": ["tag:server"]},
        "nodekey:mac2": {"ID": "nMac2", "HostName": "voicetotext-mac-air", "DNSName": "voicetotext-mac-air.tail1.ts.net.",
                         "TailscaleIPs": ["100.64.0.5"], "UserID": 11, "Online": false},
        "nodekey:mac3": {"ID": "nMac3", "HostName": "voicetotext-mac-office", "DNSName": "voicetotext-mac-office-1.tail1.ts.net.",
                         "TailscaleIPs": ["100.64.0.6"], "UserID": 11, "Online": true},
        "nodekey:bobmac": {"ID": "nBobMac", "HostName": "voicetotext-mac-bob", "DNSName": "voicetotext-mac-bob.tail1.ts.net.",
                           "TailscaleIPs": ["100.64.0.7"], "UserID": 22, "Online": true}
      },
      "User": {
        "11": {"ID": 11, "LoginName": "ann@example.com", "DisplayName": "Ann"},
        "22": {"ID": 22, "LoginName": "bob@example.com", "DisplayName": "Bob"}
      }
    }
    """#

    private static func decodesTailnetStatus() throws {
        let status = try TailnetStatus.decode(Data(fixture.utf8))
        try expect(status.backendState == "Running", "backend state")
        try expect(status.selfNode?.userID == 11, "this node's owner")
        try expect(status.peers.count == 6, "every peer")
        try expect(status.accountName == "ann@example.com", "the signed-in login")
        try expect(status.peer(withAddress: "100.64.0.2")?.id == "nPhone", "a peer by IPv4")
        try expect(status.peer(withAddress: "[fd7a:115c:a1e0::2]")?.id == "nPhone", "a peer by bracketed IPv6")
        try expect(status.peer(withAddress: "100.64.0.2:51234")?.id == "nPhone", "a peer by address and port")
        try expect(status.peer(withAddress: "[FD7A:115C:A1E0::2]:443")?.id == "nPhone", "IPv6 case and port")
        try expect(status.peer(withAddress: "100.64.0.99") == nil, "an unknown address")
        try expect(status.ownMacs.map(\.id) == ["nMac3", "nMac2"], "own Macs only, online first; no tagged or foreign ones")
        try expect(status.ownMacs.first?.machineName == "voicetotext-mac-office-1", "the machine name comes from DNS")
        try expect(status.ownMacs.first?.preferredAddress == "100.64.0.6", "IPv4 is preferred")

        let empty = try TailnetStatus.decode(Data(#"{"BackendState":"NeedsLogin","AuthURL":"https://login.tailscale.com/a/x"}"#.utf8))
        try expect(empty.peers.isEmpty && empty.selfNode == nil && empty.accountName == nil, "a signed-out status decodes")
    }

    private static func allowsOnlyTheSameUser() throws {
        let status = try TailnetStatus.decode(Data(fixture.utf8))
        guard case .allow(let phone) = RemoteAccessPolicy.decide(remoteAddress: "100.64.0.2", status: status) else {
            throw RemoteProtocolHarnessFailure(description: "the owner's phone is allowed")
        }
        try expect(phone.id == "nPhone", "the allowed peer is the phone")
        guard case .allow = RemoteAccessPolicy.decide(remoteAddress: "[fd7a:115c:a1e0::2]", status: status) else {
            throw RemoteProtocolHarnessFailure(description: "the owner's phone over IPv6 is allowed")
        }
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "100.64.0.3", status: status) else {
            throw RemoteProtocolHarnessFailure(description: "another user's device is refused")
        }
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "100.64.0.4", status: status) else {
            throw RemoteProtocolHarnessFailure(description: "a tagged device is refused even with the same owner id")
        }
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "100.64.0.99", status: status) else {
            throw RemoteProtocolHarnessFailure(description: "an unknown address is refused")
        }
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "", status: status) else {
            throw RemoteProtocolHarnessFailure(description: "no address is refused")
        }
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "127.0.0.1", status: status) else {
            throw RemoteProtocolHarnessFailure(description: "loopback isn't a peer")
        }

        let stopped = try TailnetStatus.decode(Data(fixture.replacingOccurrences(of: #""BackendState": "Running""#, with: #""BackendState": "NeedsLogin""#).utf8))
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "100.64.0.2", status: stopped) else {
            throw RemoteProtocolHarnessFailure(description: "nothing is allowed while signed out")
        }
        let taggedSelf = fixture.replacingOccurrences(of: #""UserID": 11, "Online": true, "NewFieldFromTheFuture": 3"#, with: #""UserID": 11, "Online": true, "Tags": ["tag:mac"]"#)
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "100.64.0.2", status: try TailnetStatus.decode(Data(taggedSelf.utf8))) else {
            throw RemoteProtocolHarnessFailure(description: "a tagged Mac serves nobody")
        }
        let ownerless = fixture.replacingOccurrences(of: #""UserID": 11, "Online": true, "NewFieldFromTheFuture": 3"#, with: #""Online": true"#)
        guard case .deny = RemoteAccessPolicy.decide(remoteAddress: "100.64.0.2", status: try TailnetStatus.decode(Data(ownerless.utf8))) else {
            throw RemoteProtocolHarnessFailure(description: "a Mac with no known owner serves nobody")
        }
    }

    private static func derivesTailnetState() throws {
        let url = URL(string: "https://login.tailscale.com/a/abc")!
        func derive(_ state: String, auth: String = "", browse: URL? = nil, asked: Bool = false, account: String? = nil) -> TailnetState {
            TailnetState.derive(backendState: state, authURL: auth, browseURL: browse, loginRequested: asked, accountName: account)
        }
        try expect(derive("Running", account: "ann@example.com") == .running(account: "ann@example.com"), "running")
        try expect(derive("Running") == .running(account: "Tailscale"), "running without a known account")
        try expect(derive("NeedsLogin", auth: url.absoluteString) == .signedOut, "a pending URL isn't shown until asked for")
        try expect(derive("NeedsLogin", auth: url.absoluteString, asked: true) == .needsLogin(url), "the status URL once asked")
        try expect(derive("NeedsLogin", browse: url, asked: true) == .needsLogin(url), "the bus URL once asked")
        try expect(derive("NeedsLogin", asked: true) == .connecting, "asked, no URL yet")
        try expect(derive("Stopped") == .signedOut, "stopped is signed out")
        try expect(derive("Starting") == .starting, "starting")
        try expect(derive("NoState", asked: true) == .connecting, "asked while starting")
        if case .failed = derive("NeedsMachineAuth") {} else {
            throw RemoteProtocolHarnessFailure(description: "machine approval is a failure with a reason")
        }
        try expect(derive("Running").isRunning && !derive("Starting").isRunning, "isRunning")
    }
}
