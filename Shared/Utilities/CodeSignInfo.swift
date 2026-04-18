//
//  CodeSignInfo.swift
//  Shared
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
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
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
