import Foundation

struct ExternalAPIProtocolHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ExternalAPIProtocolHarnessFailure(description: message)
    }
}

private func object(_ line: Data) throws -> [String: Any] {
    try expect(line.last == 0x0A, "every message ends with a newline")
    let json = try JSONSerialization.jsonObject(with: line.dropLast())
    guard let object = json as? [String: Any] else {
        throw ExternalAPIProtocolHarnessFailure(description: "message is a JSON object")
    }
    return object
}

@main
struct ExternalAPIProtocolHarness {
    static func main() throws {
        try parsesRequestsWithNumberAndStringIDs()
        try reportsMalformedRequestsWithTheirID()
        try encodesResponsesFailuresAndEvents()
        try splitsLinesAcrossChunks()
        try overlongLineClosesTheBuffer()
        print("External API protocol harness passed")
    }

    private static func parsesRequestsWithNumberAndStringIDs() throws {
        let numbered = ExternalAPI.parseRequest(Data(#"{"id":7,"method":"start","params":{"client":"lpm"}}"#.utf8))
        guard case .success(let start) = numbered else {
            throw ExternalAPIProtocolHarnessFailure(description: "start parses")
        }
        try expect(start == ExternalAPI.Request(id: .number(7), method: .start, client: "lpm"), "start keeps id and client")

        guard case .success(let status) = ExternalAPI.parseRequest(Data(#"{"id":"a1","method":"status"}"#.utf8)) else {
            throw ExternalAPIProtocolHarnessFailure(description: "status parses")
        }
        try expect(status.id == .string("a1"), "string ids round-trip")
        try expect(status.client == nil, "client is optional")

        guard case .success(let anonymous) = ExternalAPI.parseRequest(Data(#"{"method":"cancel"}"#.utf8)) else {
            throw ExternalAPIProtocolHarnessFailure(description: "a request without an id parses")
        }
        try expect(anonymous.id == nil, "a missing id stays missing")

        guard case .success(let boolID) = ExternalAPI.parseRequest(Data(#"{"id":true,"method":"stop"}"#.utf8)) else {
            throw ExternalAPIProtocolHarnessFailure(description: "a boolean id still parses the request")
        }
        try expect(boolID.id == nil, "a boolean is not a request id")
    }

    private static func reportsMalformedRequestsWithTheirID() throws {
        guard case .failure(let notJSON) = ExternalAPI.parseRequest(Data("hello".utf8)) else {
            throw ExternalAPIProtocolHarnessFailure(description: "plain text is rejected")
        }
        try expect(notJSON.code == .invalidRequest && notJSON.id == nil, "plain text is an invalid request")

        guard case .failure(let noMethod) = ExternalAPI.parseRequest(Data(#"{"id":3}"#.utf8)) else {
            throw ExternalAPIProtocolHarnessFailure(description: "a request without a method is rejected")
        }
        try expect(noMethod.code == .invalidRequest && noMethod.id == .number(3), "missing method keeps the id")

        guard case .failure(let unknown) = ExternalAPI.parseRequest(Data(#"{"id":4,"method":"paste"}"#.utf8)) else {
            throw ExternalAPIProtocolHarnessFailure(description: "an unknown method is rejected")
        }
        try expect(unknown.code == .unknownMethod && unknown.id == .number(4), "unknown method keeps the id")
    }

    private static func encodesResponsesFailuresAndEvents() throws {
        let response = try object(ExternalAPI.response(id: .number(1), result: ["state": "idle"]))
        try expect(response["id"] as? Int == 1, "response echoes the id")
        try expect(response["ok"] as? Bool == true, "response is ok")
        try expect((response["result"] as? [String: Any])?["state"] as? String == "idle", "response carries the result")

        let failure = try object(ExternalAPI.failure(id: .string("x"), code: .busy, message: "Busy."))
        try expect(failure["id"] as? String == "x", "failure echoes the id")
        try expect(failure["ok"] as? Bool == false, "failure is not ok")
        let error = failure["error"] as? [String: Any]
        try expect(error?["code"] as? String == "busy" && error?["message"] as? String == "Busy.", "failure carries code and message")

        let anonymous = try object(ExternalAPI.failure(id: nil, code: .invalidRequest, message: "Bad."))
        try expect(anonymous["id"] == nil, "a failure without an id omits it")

        let event = try object(ExternalAPI.event("transcript", ["text": "Hello / world"]))
        try expect(event["event"] as? String == "transcript", "event names itself")
        try expect(event["text"] as? String == "Hello / world", "event carries its fields")
        try expect(event["id"] == nil, "events have no id")
        let raw = String(decoding: ExternalAPI.event("partial", ["text": "a/b"]), as: UTF8.self)
        try expect(!raw.contains("\\/"), "slashes are not escaped")
    }

    private static func splitsLinesAcrossChunks() throws {
        var splitter = ExternalAPI.LineSplitter()
        try expect(splitter.append(Data(#"{"id":1,"me"#.utf8)).isEmpty, "a partial line waits")
        let lines = splitter.append(Data("thod\":\"status\"}\r\n\n  \n{\"id\":2,\"method\":\"stop\"}\n{\"id\"".utf8))
        try expect(lines.count == 2, "two complete lines, blank lines skipped")
        try expect(String(decoding: lines[0], as: UTF8.self) == #"{"id":1,"method":"status"}"#, "CRLF is trimmed")
        try expect(String(decoding: lines[1], as: UTF8.self) == #"{"id":2,"method":"stop"}"#, "second line intact")
        let rest = splitter.append(Data(":3,\"method\":\"cancel\"}\n".utf8))
        try expect(rest.count == 1, "the trailing partial completes")
        try expect(!splitter.overflowed, "ordinary traffic never overflows")
    }

    private static func overlongLineClosesTheBuffer() throws {
        var splitter = ExternalAPI.LineSplitter()
        _ = splitter.append(Data(repeating: 0x61, count: ExternalAPI.maxLineBytes + 1))
        try expect(splitter.overflowed, "a line past the cap overflows")
        try expect(splitter.append(Data("{\"method\":\"status\"}\n".utf8)).isEmpty, "nothing is read after an overflow")
    }
}
