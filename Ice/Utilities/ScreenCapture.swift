//
//  ScreenCapture.swift
//  Ice
//

import CoreGraphics
import OSLog
import ScreenCaptureKit

private let logger = Logger(subsystem: "com.jordanbaird.Ice", category: "ScreenCapture")

/// A namespace for screen capture operations.
enum ScreenCapture {

    // MARK: Permissions

    /// Cached result from the most recent async SCShareableContent permission check.
    /// `nil` until the first async check completes.
    nonisolated(unsafe) private static var _asyncPermissionResult: Bool? = nil

    /// Triggers an async SCShareableContent check and updates `_asyncPermissionResult`.
    /// Safe to call on every timer tick; each call spawns a detached Task.
    static func refreshPermissionsAsync() {
        Task {
            do {
                _ = try await SCShareableContent.current
                logger.debug("SCShareableContent.current succeeded → permission granted")
                _asyncPermissionResult = true
            } catch {
                logger.debug("SCShareableContent.current threw: \(error, privacy: .public) → permission denied")
                _asyncPermissionResult = false
            }
        }
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    static func checkPermissions() -> Bool {
        // Kick off an async refresh so the next call (≥1 s later via the Permission
        // timer) picks up the latest granted state — reliable on macOS 26 where the
        // synchronous fallbacks below reflect only the launch-time state.
        refreshPermissionsAsync()

        // Prefer the async result once it's available.
        if let asyncResult = _asyncPermissionResult {
            return asyncResult
        }

        // Synchronous fallbacks — accurate on earlier macOS or at first launch.
        for windowID in Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace]) {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            let titleResult = window.title != nil
            logger.debug("window title check → \(titleResult, privacy: .public) (title: \(window.title ?? "<nil>", privacy: .public))")
            return titleResult
        }
        let preflightResult = CGPreflightScreenCaptureAccess()
        logger.debug("CGPreflightScreenCaptureAccess → \(preflightResult, privacy: .public)")
        return preflightResult
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent
    /// calls. Pass `true` to the `reset` parameter to replace the cached
    /// result with a newly computed value.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        enum Context {
            static var cachedResult: Bool?
        }
        if !reset, let result = Context.cachedResult, result {
            return result
        }
        let result = checkPermissions()
        Context.cachedResult = result
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        if #available(macOS 15.0, *) {
            // CGRequestScreenCaptureAccess() is broken on macOS 15. We can
            // try accessing SCShareableContent to trigger a request if the
            // user doesn't have permissions.
            // TODO: Find out if we still need this as of macOS 26.
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Capture Window(s)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited from front to back, according to the order
    /// of the `windowIDs` parameter.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            return nil
        }
        let bounds = screenBounds ?? .null
        // ScreenCaptureKit doesn't support capturing images of offscreen menu bar
        // items, so we unfortunately have to use the deprecated CGWindowList API.
        return CGImage(windowListFromArrayScreenBounds: bounds, windowArray: array, imageOption: option)
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify which parts of the window are captured.
    static func captureWindow(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows(with: [windowID], screenBounds: screenBounds, option: option)
    }
}
