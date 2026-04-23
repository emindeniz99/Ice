//
//  Permission.swift
//  Ice
//

import Combine
import Cocoa

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
class Permission: ObservableObject, Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    @Published private(set) var hasPermission = false

    /// The title of the permission.
    let title: String

    /// Descriptive details for the permission.
    let details: [String]

    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool

    /// A Boolean value that indicates whether the app may need to relaunch
    /// before this permission becomes usable. On macOS 26 Screen Recording
    /// sometimes only takes effect after a relaunch.
    let mayRequireRelaunch: Bool

    /// The URLs of the settings panes to try to open, in order of preference.
    private let settingsURLs: [URL]

    /// The function that checks permissions.
    private let check: () -> Bool

    /// The function that requests permissions.
    private let request: () -> Void

    /// Observer that runs on a timer to check permissions.
    private var timerCancellable: AnyCancellable?

    /// Observer that observes the ``hasPermission`` property.
    private var hasPermissionCancellable: AnyCancellable?

    /// Creates a permission.
    init(
        title: String,
        details: [String],
        isRequired: Bool,
        mayRequireRelaunch: Bool = false,
        settingsURLs: [URL] = [],
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
        self.isRequired = isRequired
        self.mayRequireRelaunch = mayRequireRelaunch
        self.settingsURLs = settingsURLs
        self.check = check
        self.request = request
        self.hasPermission = check()
        configureCancellables()
    }

    /// Sets up the internal observers for the permission.
    private func configureCancellables() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .merge(with: Just(.now))
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                hasPermission = check()
            }
    }

    /// Performs the request and opens the System Settings app to the appropriate pane.
    func performRequest() {
        request()
        openSettingsPane()
    }

    /// Opens the most relevant System Settings pane for the permission.
    ///
    /// On macOS 26 the URL scheme for Privacy panes has shifted from the
    /// legacy `com.apple.preference.security` bundle to
    /// `com.apple.settings.PrivacySecurity.extension`. Some point releases
    /// accept both; others only the new form. We try the new URLs first,
    /// then the legacy one, and finally shell out to `/usr/bin/open` to
    /// bypass any NSWorkspace registration glitches.
    func openSettingsPane() {
        guard !settingsURLs.isEmpty else {
            return
        }

        // Give the Settings app a chance to launch before we ask it to
        // open a specific pane — on macOS 26 the pane URL is sometimes
        // ignored if Settings wasn't already running.
        if #available(macOS 13, *) {
            let settingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: settingsAppURL, configuration: configuration)
        }

        for url in settingsURLs where NSWorkspace.shared.open(url) {
            return
        }

        for url in settingsURLs {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [url.absoluteString]
            do {
                try process.run()
                return
            } catch {
                continue
            }
        }
    }

    /// Asynchronously waits for the app to be granted this permission.
    func waitForPermission() async {
        configureCancellables()
        guard !hasPermission else {
            return
        }
        return await withCheckedContinuation { continuation in
            hasPermissionCancellable = $hasPermission.sink { [weak self] hasPermission in
                guard let self else {
                    continuation.resume()
                    return
                }
                if hasPermission {
                    hasPermissionCancellable?.cancel()
                    continuation.resume()
                }
            }
        }
    }

    /// Stops running the permission check.
    func stopCheck() {
        timerCancellable?.cancel()
        timerCancellable = nil
        hasPermissionCancellable?.cancel()
        hasPermissionCancellable = nil
    }
}

// MARK: - AccessibilityPermission

final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: "Accessibility",
            details: [
                "Get real-time information about the menu bar.",
                "Arrange menu bar items.",
            ],
            isRequired: true,
            check: {
                AXHelpers.isProcessTrusted()
            },
            request: {
                AXHelpers.isProcessTrusted(prompt: true)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: "Screen Recording",
            details: [
                "Change the menu bar's appearance.",
                "Display images of individual menu bar items.",
            ],
            isRequired: false,
            mayRequireRelaunch: true,
            settingsURLs: [
                // Preferred macOS 26+ URL (new Privacy extension bundle).
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
                // Same extension, fall back to the Privacy landing page.
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy",
                // Legacy URL kept for earlier macOS and as a last resort.
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            ].compactMap { URL(string: $0) },
            check: {
                ScreenCapture.checkPermissions()
            },
            request: {
                ScreenCapture.requestPermissions()
            }
        )
    }
}
