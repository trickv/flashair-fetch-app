import Foundation
import Sentry

/// Thin wrapper around the Sentry SDK. The rest of the app calls into this
/// instead of importing `Sentry` directly, so we keep SDK-specific knowledge
/// in one place and can stub it for tests.
///
/// **Telemetry is opt-in.** Nothing leaves the device until the user flips the
/// Settings -> Privacy toggle. Even with the toggle on we configure Sentry
/// conservatively for a personal photo app:
///   - no Session Replay (records UI — too invasive)
///   - no `attachScreenshot` / `attachViewHierarchy` (could capture photos)
///   - `sendDefaultPii = false` (no IP / user info)
///   - no profiling (overhead not justified yet)
///
/// What gets sent when enabled: crash reports, app-hang events,
/// `FlashAirError`-derived events, breadcrumbs from `Logger.shared`, and one
/// `sync_completed` event per finished sync containing only aggregate
/// counts/durations. No filenames, no photo content, no personal info.
enum Telemetry {

    // MARK: - Lifecycle

    /// Start Sentry unless the user has explicitly opted out. Called from
    /// app launch. `nil` (never touched the toggle) and `true` both start
    /// the SDK; only an explicit `false` skips it.
    @MainActor
    static func startIfEnabled() {
        guard UserDefaults.standard.syncSettings.telemetryEnabled != false else { return }
        start()
    }

    /// Force-start the SDK (used by the Settings toggle when the user enables
    /// telemetry mid-session). Crash and app-hang handlers installed mid-run
    /// only catch events from this point forward — full coverage from the
    /// next app launch.
    @MainActor
    static func start() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              dsn.hasPrefix("https://") else {
            print("⚠️ Telemetry: SentryDSN missing or malformed in Info.plist; not starting Sentry")
            return
        }
        #if DEBUG
        let envName = "debug"
        #else
        let envName = "release"
        #endif
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = envName

            // What we want
            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.tracesSampleRate = 0.2 as NSNumber  // 20% of transactions

            // What we deliberately do NOT want, for privacy
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.sendDefaultPii = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
        }
        print("✅ Telemetry: Sentry started (env=\(envName))")
    }

    /// Stop the SDK. Used by the Settings toggle when the user disables
    /// telemetry mid-session. Drops any in-flight events.
    @MainActor
    static func stop() {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.close()
        print("🛑 Telemetry: Sentry stopped")
    }

    /// Whether the SDK is currently initialized and accepting events.
    static var isActive: Bool { SentrySDK.isEnabled }

    // MARK: - Event capture (all calls are no-ops when SDK isn't started)

    /// Add a breadcrumb to the trail leading up to any captured error.
    /// Wired up from `Logger.shared.log` so existing log lines become
    /// breadcrumb context automatically.
    static func breadcrumb(_ message: String, level: LogLevel = .info, category: String = "log") {
        guard SentrySDK.isEnabled else { return }
        let crumb = Breadcrumb()
        crumb.message = message
        crumb.level = level.sentryLevel
        crumb.category = category
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Capture an error as a Sentry event with optional extra context.
    static func capture(_ error: Error, extra: [String: Any]? = nil) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            if let extra = extra {
                for (k, v) in extra {
                    scope.setExtra(value: v, key: k)
                }
            }
        }
    }

    /// Emit a structured `sync_completed` event describing the outcome of
    /// a finished sync. Aggregate numbers only — no filenames, no photo
    /// content, no personal info.
    static func captureSyncCompleted(
        totalFiles: Int,
        importedCount: Int,
        alreadySyncedCount: Int,
        skippedCount: Int,
        failedCount: Int,
        totalBytes: Int,
        duration: TimeInterval
    ) {
        guard SentrySDK.isEnabled else { return }
        let throughputMbps: Double = duration > 0
            ? Double(totalBytes) * 8.0 / duration / 1_000_000
            : 0
        SentrySDK.capture(message: "sync_completed") { scope in
            scope.setLevel(.info)
            scope.setTag(value: failedCount > 0 ? "partial" : "success", key: "sync_outcome")
            scope.setExtra(value: totalFiles, key: "total_files")
            scope.setExtra(value: importedCount, key: "imported_count")
            scope.setExtra(value: alreadySyncedCount, key: "already_synced_count")
            scope.setExtra(value: skippedCount, key: "skipped_count")
            scope.setExtra(value: failedCount, key: "failed_count")
            scope.setExtra(value: totalBytes, key: "total_bytes")
            scope.setExtra(value: Int(duration), key: "duration_seconds")
            scope.setExtra(value: String(format: "%.2f", throughputMbps), key: "throughput_mbps")
        }
    }
}

// MARK: - LogLevel bridge

private extension LogLevel {
    /// Map our `Logger`'s `LogLevel` to `SentryLevel` for breadcrumb leveling.
    var sentryLevel: SentryLevel {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .warning
        case .error:   return .error
        }
    }
}
