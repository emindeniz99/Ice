//
//  CodeSignInfo.swift
//  Shared
//
//  Inspects the current process's code signature so the rest of the app
//  can decide whether to apply XPC peer requirements that depend on a
//  real Apple team identifier.
//

import Foundation
import Security

/// Helpers for inspecting the current process's code signature.
enum CodeSignInfo {
    /// Returns the team identifier of the current process, or `nil` when the
    /// process is ad-hoc signed (or not signed at all).
    ///
    /// The result is cached after the first computation, since the team ID
    /// does not change during a single run of the process.
    static let currentTeamIdentifier: String? = {
        var codeRef: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &codeRef) == errSecSuccess,
              let code = codeRef
        else {
            return nil
        }

        var staticCodeRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCodeRef) == errSecSuccess,
              let staticCode = staticCodeRef
        else {
            return nil
        }

        var infoRef: CFDictionary?
        // kSecCSSigningInformation is defined as `1 << 1` by the Security
        // framework. We use the literal value here to avoid depending on
        // how Swift imports the constant (`Int`, `UInt32`, or `SecCSFlags`),
        // which has varied between toolchains.
        let flags = SecCSFlags(rawValue: 1 << 1)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any]
        else {
            return nil
        }

        guard let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty
        else {
            return nil
        }
        return teamID
    }()

    /// `true` when the current process has a team identifier in its signature.
    /// Peer-to-peer `XPC` requirements such as `.isFromSameTeam()` only make
    /// sense when the process has one.
    static var hasTeamIdentifier: Bool {
        currentTeamIdentifier != nil
    }
}
