# Apple Watch app

The **SplitXWatch** watchOS target is set up in `SplitX.xcodeproj` and embedded
in the SplitX iPhone app ("Embed Watch Content" build phase). Building the
**SplitX** scheme builds both apps. Use the **SplitXWatch** scheme to run on a
Watch.

| Path | Target(s) |
|---|---|
| `Shared/WatchShared.swift` | SplitX **and** SplitXWatch |
| `SplitX/WatchSessionManager.swift`, `WatchSettingsStore.swift`, `WatchSettingsView.swift` | SplitX |
| `WatchApp/*.swift`, `WatchApp/Assets.xcassets`, `WatchApp/Info.plist` | SplitXWatch |

- Bundle ID: `yourcompany.SharedExpenses.watchkitapp`. Team 94PZKL85KB, automatic signing.
- watchOS 10.0+. No Swift packages: the Watch has no Supabase or ads.
- **Versions must match the iPhone app**, or App Store validation rejects the
  upload. Both Info.plists read `$(MARKETING_VERSION)` and
  `$(CURRENT_PROJECT_VERSION)`, which are set once at the project level. Bump
  them in Project ▸ SplitX ▸ Build Settings, not in a target's General tab.
- The Watch icon is a flattened copy (no alpha channel) of the iOS 1024 icon.

## Run on your iPhone + Apple Watch

1. Connect the iPhone by cable (or over Wi-Fi), unlock it, and trust the Mac.
   Keep the Watch unlocked and near the iPhone. Developer Mode must be on for
   both (Settings ▸ Privacy & Security).
2. In Xcode, pick the **SplitX** scheme ▸ your iPhone ▸ Run. This installs the
   iPhone app.
3. Pick the **SplitXWatch** scheme ▸ your Apple Watch ▸ Run. This installs the
   Watch app. The first run on a new Watch can take several minutes while Xcode
   copies debug symbols.

## Try it

1. Without Premium, the Watch shows "SplitX Premium", and Settings ▸ Apple Watch
   on the iPhone is locked.
2. With Premium: on the iPhone, go to Settings ▸ Apple Watch, pick a group,
   check the paid-by and split, and tap Save.
3. On the Watch, tap **+**, write the description (Scribble or dictation), type
   the amount, and tap ✓. The expense appears in that group on the iPhone.
   - Larger Watches open the keyboard first. The button at the bottom right
     switches to Scribble.

## How it works

- iPhone → Watch (`updateApplicationContext`): whether Premium is active, the
  chosen group, and its currency.
- Watch → iPhone: the description and amount, sent two ways. `sendMessage`
  wakes the iPhone app in the background (no need to open it, even when the
  phone is locked) and waits for the result, which the Watch's confirmation
  screen shows. `transferUserInfo` keeps a queued copy as a fallback. Once the
  iPhone confirms, the copy is cancelled. If the iPhone is out of range, the
  Watch resends when it's back, and the iPhone saves each expense only once.
- The iPhone applies the paid-by and split from Settings ▸ Apple Watch. If those
  don't add up to 100% across the current members, it uses the group's defaults,
  and failing that an even split.
- Before saving, the iPhone checks Premium and the yearly cap again. A rejection
  shows on the Watch's confirmation screen. If the Watch can't get the answer,
  the iPhone posts a notification instead.

## Watch face complication (SplitXComplication)

A WidgetKit complication that puts SplitX on the watch face; tapping it launches
the Watch app (watchOS launches a complication's owning app for you), which
opens to the **+** add-expense screen. It carries no live data.

| Path | Target |
|---|---|
| `WatchComplication/SplitXComplication.swift`, `WatchComplication/Info.plist` | SplitXComplication |

The **SplitXComplication** widget-extension target is wired into the project.
Like the Watch target, it was added by a **careful hand edit** of
`project.pbxproj` (IDs `AAAA…0Bxx`), **not** xcodegen — a Widget Extension is a
whole new target and this `.xcodeproj` is hand-maintained. The pieces:

- **Target** `SplitXComplication`, product type
  `com.apple.product-type.app-extension`, `SDKROOT = watchos`,
  `WATCHOS_DEPLOYMENT_TARGET = 10.0`, `TARGETED_DEVICE_FAMILY = 4`,
  `SWIFT_VERSION = 5.0`, automatic signing, `INFOPLIST_FILE =
  WatchComplication/Info.plist`. Its Info.plist declares the one required key,
  `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
- **Bundle id** `yourcompany.SharedExpenses.watchkitapp.SplitXComplication` —
  the Watch app's id plus `.SplitXComplication`. A watch-face complication's
  extension **must** be a child of, and embedded in, the Watch app.
- **Embedded in SplitXWatch** (not SplitX) via an "Embed Foundation Extensions"
  copy-files phase (`dstSubfolderSpec = 13`, i.e. PlugIns) on the SplitXWatch
  target, plus a SplitXWatch → SplitXComplication target dependency. At build
  time the appex lands in `SplitXWatch.app/PlugIns/SplitXComplication.appex`.
- **Versioning:** no `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` on the
  target, so it inherits the project-level values (its Info.plist reads the
  variables), keeping it in lockstep with the iPhone and Watch apps as App Store
  validation requires.
- Only `SplitXComplication.swift` is in the target's Sources phase. No Swift
  packages, no entitlements, no WatchConnectivity, no asset catalog — it is
  purely a launcher and imports nothing from the Watch app.

To try it: build the **SplitXWatch** scheme to a Watch (or Simulator), then on
the watch long-press the face ▸ Edit ▸ add a complication slot ▸ pick **SplitX**.
Tapping it opens the Watch app on the **+** add-expense screen.
