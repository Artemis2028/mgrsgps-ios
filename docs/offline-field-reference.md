# Offline Field Reference

Compared directly with Android release/1.1.0 `ReferenceScreen.kt` on482b417.
The source audit found no matching iOS pocket-reference screen. iOS now has
all seven topics: phonetic alphabet/digits, radio-grid example, MGRS reading,
pace count/condition reminders, seven contour shapes, north-reference conversion
reminders, and unit affiliation/echelon/night identification.

The page opens from Settings and Map tools. It is bundled text and uses the
existing Phonetic tables/speech-group formatter; it needs no network, location
permission, running navigation or provider. Reading it does not change saved
records, targets, active route progress or quiet-inside state. Opening it from
Map tools also leaves an existing lasso selection intact.

Native Liquid Glass cards have explicit expanded/collapsed accessible headers.
Alphabet/digit tables use two columns when they fit and a single column when
the native Dynamic Type environment requires it. Day/night colors follow the
app. The training/SOP note is retained. Precision is explicitly distinguished
from GPS accuracy; pace-condition reminders are qualified so they do not replace
a measured pace count. Contour descriptions avoid naming an Android-only HUD
location for its interval label. North-reference signs match the app's existing
true/grid/magnetic conversion rules.

Validation:

- `/tmp/mgrsgps-export-reference-final.xcresult`: all346 native cases pass
  (four opt-in skips), plus day/night reference navigation and all seven topic
  expansion checks, radio spelling/accuracy note, PDF Save/share and preserved-
  original sharing. Final-source day/night reference checks repeat successfully
  in `/tmp/mgrsgps-reference-layout-final.xcresult` after completing the pace
  condition rows/index-contour reminder. Repeats are not extra distinct cases.
- The global AccessibilityXXXL attempts fail before reaching the reference.
  Recorded Settings-helper navigation enters Guide settings; the map launch
  demonstrates genuinely overflowing map HUD text/icons. These failures remain
  failures and expose real separate app layout work. See the parity checklist.
- `/tmp/mgrsgps-reference-isolated-accessibility.xcresult` then passes the
  reference-only largest Dynamic Type check. Its opt-in DEBUG flag, restricted
  to uiTesting, changes only this page's SwiftUI environment. Assertions require
  a visibly larger native text frame and matching horizontal source positions
  for the first/last alphabet rows; normal text cannot satisfy it. The actual
  screenshot shows one readable scrollable column. This is page-layout evidence,
  not proof that global app navigation supports the largest category.
- Day/night alphabet, grid, north and symbol captures, plus the final largest-
  type image, are inspected. Final phone/watch/widget unsigned device Release
  and eight Python harness checks pass. All local parents naturally terminal;
  owned devices/fake feeds off.

The combined export/reference work validates22 distinct UI workflows across
bundles:19 existing export/recovery cases and three reference cases. Earlier
PDF/ShareLink expectation mistakes and global accessibility navigation failures
are retained, not relabelled as successful runs. Full hosted confirmation,
physical spoken VoiceOver and whole-app accessibility-size layout remain open.
