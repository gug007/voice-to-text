import Foundation
import Security

/// What the running build's own code signature says about it, and whether
/// another bundle's signature matches it.
nonisolated enum CodeSigning {
    /// The running build's signing team, or nil when it has none: unsigned,
    /// or ad-hoc signed (Xcode's "Sign to Run Locally", or the linker's own
    /// signature on an unsigned build). Such a build's designated requirement is
    /// a hash of this exact binary, so nothing else can ever satisfy it.
    static let runningTeamIdentifier: String? = {
        guard let code = runningStaticCode() else { return nil }
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard status == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else { return nil }
        return team
    }()

    /// The running app's designated requirement: its identifier plus the exact
    /// certificate chain it was signed with, as the signing tools wrote it. An
    /// update is held to this rather than to a hand-written requirement, so it
    /// can't drift from how releases are really signed. Nil for a build with no
    /// signing team (see `runningTeamIdentifier`).
    static func runningDesignatedRequirement() -> SecRequirement? {
        guard runningTeamIdentifier != nil, let code = runningStaticCode() else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess else {
            return nil
        }
        return requirement
    }

    /// Checks the bundle at `url` is intact — every architecture, nested code
    /// and sealed resource — and satisfies `requirement`. Returns nil when it
    /// does, or a description of the failure for the log.
    static func validationFailure(ofBundleAt url: URL, against requirement: SecRequirement) -> String? {
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard createStatus == errSecSuccess, let code else {
            return describe(createStatus)
        }
        let flags = SecCSFlags(rawValue:
            kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode
        )
        var error: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &error)
        guard status != errSecSuccess else { return nil }
        let detail = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String }
        return detail.map { "\(describe(status)): \($0)" } ?? describe(status)
    }

    private static func runningStaticCode() -> SecStaticCode? {
        var running: SecCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(running, [], &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    private static func describe(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String?
        return "\(message ?? "Code signing error") (\(status))"
    }
}
