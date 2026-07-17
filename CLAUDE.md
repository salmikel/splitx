# SplitX — project notes for Claude

Shared-expense iOS app (SwiftUI, `ios/SplitX/`) with a Next.js web app + Supabase
backend (`web/`, `supabase/`). Being prepared for paid App Store release.

## iOS build — critical gotchas

- **Do NOT run `xcodegen generate` on this project.** The `.xcodeproj` is
  hand-maintained in Xcode; `ios/SplitX/project.yml` is **stale and unused**.
  Regenerating overwrites the real project and breaks it — it resets the bundle
  ID, and drops the Sign in with Apple entitlements, accent color, and app-icon
  settings. To add source files or packages, do it **through Xcode**, not xcodegen.

- **Real bundle identifier is `yourcompany.SharedExpenses`** (that's the app on
  TestFlight/App Store Connect). `project.yml` wrongly says `com.splitx.app` —
  ignore it. Changing the bundle ID makes TestFlight see a new app, and would
  also require updating the Supabase Apple provider's authorized client IDs.

- **AdMob / error 90208 (`UserMessagingPlatform` MinimumOSVersion 100.0):** the
  GoogleMobileAds SPM package bundles `UserMessagingPlatform`, whose Info.plist
  ships a bogus `MinimumOSVersion = 100.0`, failing App Store validation. Fixed
  by a Run Script build phase named **"Fix framework MinimumOSVersion"** (last
  phase, "based on dependency analysis" unchecked) that rewrites any
  framework's `MinimumOSVersion` of `100.0` to `${IPHONEOS_DEPLOYMENT_TARGET}`
  and re-signs it. If that phase goes missing, uploads will fail again.

- Deployment target is **iOS 17.0**. GoogleMobileAds pinned to **v12+** (API has
  no `GAD` prefix: `InterstitialAd`, `Request`, `MobileAds.shared`).

- Stale `.pcm` / "module.modulemap has been modified" errors after adding a
  binary SPM package: clear DerivedData + File → Packages → Reset Package Caches.

## Backend

- Supabase project ref: `jxcbchqewasrqjatznci` (name "splitx"). Security is
  entirely RLS-based; the hardcoded anon key in `SupabaseService.swift` is public
  by design. Edge functions deployed: `delete-account` (in-app account deletion);
  `app-store-notifications` (App Store Server Notifications V2 handler,
  verify_jwt=false, verifies Apple's JWS and writes `profiles.premium_until`).
- **Premium entitlement sync**: iOS StoreKit is the source of truth on-device;
  `profiles.premium_until` mirrors it so the web app applies the same free
  limits. Currently the iOS app writes it (forgeable). To make it tamper-proof:
  set the ASC App Store Server Notification URL (Production + Sandbox, V2) to
  `https://jxcbchqewasrqjatznci.supabase.co/functions/v1/app-store-notifications`,
  verify in sandbox, then apply migration `013_lock_premium_until.sql` AND remove
  `SubscriptionManager.syncEntitlementToProfile`. iOS purchases set
  `appAccountToken` = the user's UUID so notifications map to the account.
- Web app deploys to Cloudflare via `cd web && npm run deploy` (wrangler is
  authenticated locally).

## Monetization

- **v1.0 ships with NO ads** (free app). The GoogleMobileAds SDK triggered
  persistent App Store validation failures (error 90208 on the bundled
  `UserMessagingPlatform` / `GoogleMobileAds` frameworks' `MinimumOSVersion`)
  and was removed to unblock release. `AdManager` is now a no-op stub; the
  paywall is hidden (a "remove ads" IAP with no ads would be rejected).
- StoreKit 2 `SubscriptionManager` and `PaywallView` remain in the codebase
  (compile, StoreKit-only, not user-facing) for a future v1.1 that re-adds ads +
  the $4.99/yr subscription (product ID `com.splitx.app.premium.yearly`).
- If re-adding AdMob: the 90208 fix is that each embedded framework's Info.plist
  `MinimumOSVersion` must EQUAL its binary's `LC_BUILD_VERSION minos` (both were
  12.0); patching the SPM artifact also requires stripping its `_CodeSignature`
  (Xcode re-signs on embed) and not resetting package caches. This was flaky —
  prefer vendoring the frameworks locally or waiting for a fixed SDK release.
