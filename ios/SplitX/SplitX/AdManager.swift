import Foundation

/// Ads are disabled for the v1.0 release (the GoogleMobileAds SDK was removed).
///
/// This is a no-op stub so the existing call sites keep compiling; interstitial
/// ads can be reintroduced later by restoring the SDK and this file's logic
/// without re-plumbing the app.
@MainActor
final class AdManager: ObservableObject {
    func start() {}
    func preload() {}
    func registerCompletedAction() {}
}
