//
//  AXHelpers.swift
//  Shared
//

import AXSwift
import Cocoa

enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync { checkIsProcessTrusted(prompt: prompt) }
    }

    static func element(at point: CGPoint) -> UIElement? {
        queue.sync { try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y)) }
    }

    /// Returns the system menu bar element near the origin of a display.
    ///
    /// Single-point hit-testing at the exact display corner (0, 0) can fail on
    /// notched displays (outside the rounded-corner mask), next to menu bar
    /// accessories installed by third-party apps like NotchNook, and on macOS 26's
    /// translucent "Liquid Glass" menu bar. Probing several inset points along the
    /// leftmost region of the menu bar (where application menus live, and away
    /// from the notch and trailing accessories) is significantly more reliable.
    static func menuBarElement(nearDisplayOrigin origin: CGPoint) -> UIElement? {
        // Probe points are in screen coordinates with the origin at the top-left
        // of the display. Offsets are applied to avoid the notch area and
        // translucent pixels near the very top of the menu bar.
        let probeOffsets: [CGPoint] = [
            CGPoint(x: 20, y: 12),
            CGPoint(x: 40, y: 12),
            CGPoint(x: 80, y: 12),
            CGPoint(x: 120, y: 12),
            CGPoint(x: 20, y: 6),
            CGPoint(x: 2, y: 2),
            .zero,
        ]
        for offset in probeOffsets {
            let point = CGPoint(x: origin.x + offset.x, y: origin.y + offset.y)
            guard let element = element(at: point) else {
                continue
            }
            if role(for: element) == .menuBar {
                return element
            }
        }
        return nil
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync { Application(runningApp) }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        queue.sync { try? element.attribute(.enabled) } ?? false
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }

    static func role(for element: UIElement) -> Role? {
        queue.sync { try? element.role() }
    }
}
