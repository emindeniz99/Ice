//
//  Listener.swift
//  MenuBarItemService
//

import OSLog
import XPC

/// A wrapper around an XPC listener object.
final class Listener {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// Creates the shared listener.
    private init() { }

    deinit {
        cancel()
    }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                Logger.default.debug("Listener received start request")
                return .start
            case .sourcePID(let window):
                let pid = SourcePIDCache.shared.pid(for: window)
                return .sourcePID(pid)
            }
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        listener = try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    func activate() {
        guard listener == nil else {
            Logger.default.notice("Listener is already active")
            return
        }

        Logger.default.debug("Activating listener")

        do {
            // `.isFromSameTeam()` only succeeds when the process has a real
            // team identifier in its signature. Ad-hoc signed builds (which
            // Xcode produces by default when there's no signing team set)
            // have no team ID, so the requirement would refuse every peer
            // and the XPC channel would be unusable. Fall back to the
            // unchecked activation in that case so local builds still work.
            if #available(macOS 26.0, *), CodeSignInfo.hasTeamIdentifier {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
            }
        } catch {
            Logger.default.error("Failed to activate listener with error \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.take()?.cancel()
    }
}
