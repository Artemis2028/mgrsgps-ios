# Native app icons

iPhone/iPad and Apple Watch use the existing Android GridFix launcher mark:
the 108-unit vector in `app/src/main/res/drawable/ic_launcher_foreground.xml`
and `ic_launcher_background` from Android `release/1.1.0`. The mark keeps its
original geometry, round crosshair ticks, green `#7BC67E` and background `#0B0E13`.
There is no pre-rendered corner or circle mask; the OS supplies it.

Run `swift scripts/render-app-icons.swift` to regenerate the asset catalogs.
It draws each phone size directly with Core Graphics, explicitly in sRGB, and
writes opaque RGB PNGs. Explicit iPhone/iPad slots cover the iOS 16 deployment
target and the 1024-pixel marketing image. Watch uses its own single-size
1024-pixel AppIcon catalog; the native asset compiler supplies the watch variants.
See [Apple's asset-catalog icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).
`project.yml` includes the phone catalog and names AppIcon for both app targets;
the existing watch resource group includes its catalog.

## Verification, 26 October 2026

- All 13 phone images and the watch image are opaque RGB. Full-colour pixels
  match the Android source values exactly; explicitly selecting sRGB avoids
  implicit generic-RGB conversion changing those values.
- Regeneration from another working directory produces identical bytes.
- Final native simulator and device Release builds pass, including the embedded
  watch and Live Activities widget. Logs: `/tmp/gridfix-app-icons-final-simulator.log`
  and `/tmp/gridfix-app-icons-final-release.log`.
- Compiled phone/iPad and watch Info.plist icon metadata reference AppIcon;
  the compiled watch Assets.car contains the named icon and multisize rendition.
- Actual iPhone home-screen and 40 mm Watch app-grid icons were inspected:
  `/tmp/gridfix-phone-launcher-icon.png` and `/tmp/gridfix-watch-launcher-icon.png`.
  Watch initially retained its old placeholder in the launcher while showing
  the new icon during launch; a watch restart refreshed the launcher cache.
  No data reset or uninstall was needed.
- Only the test phone and then the test watch were needed; both are shut down.

This closes missing native launcher artwork. Store submission, signing, privacy
metadata, purchase configuration and physical device/release validation remain
separate gates. No release was made.
