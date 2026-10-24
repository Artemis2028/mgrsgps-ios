# Watch companion feature contract

Wear OS and watchOS share this functional scope. Native controls may differ to fit round and rectangular screens.

| Capability | Shared behavior |
| --- | --- |
| Current grid | Watch GPS, MGRS zone/square and both coordinate rows together on one primary screen |
| Coordinate format | Local 4/6/8/10-digit selector on the right; independent Follow phone reset |
| Fix quality | Source, reported horizontal accuracy and fix age; stale/unauthorized fixes cannot produce navigation numbers |
| Selected waypoint | Name, numeric bearing and distance; explicit phone selection clearing removes the cached target |
| References | Phone distance/angle units and true, magnetic or grid reference; unavailable magnetic reference is explicit |
| Phone connection | Cached target/settings remain usable with their age and honest connection status |
| Map | Read-only interactive map with pan/zoom/recenter, fresh watch position, cached visible waypoints and field geometry, sync age and explicit omission/simplification counts |
| Night mode | Local Day/Night/Follow phone choice, independent of the precision override |

Digit count describes coordinate formatting, not GPS accuracy. Both platforms display reported GPS accuracy separately. Neither companion currently promises a heading compass, haptic navigation, background tracking or navigation while the screen is locked. Those require their own platform-specific implementation and physical-device validation.

Small-screen simulator checks cover a 40 mm Apple Watch and a 192 dp round Wear OS device. Apple phone/watch application-context delivery has been exercised with a paired simulator. Wear OS rendering and freshness checks use an emulator; paired physical Data Layer delivery remains to be verified. Simulator evidence does not replace field, battery, permission or radio testing.

Current map implementation differences:

- watchOS uses Apple Maps and opens its interactive map full-screen from the third Map page. Wear OS uses OSM browse tiles with attribution and an MGRS grid toggle. Neither transfers phone MBTiles, downloaded map areas, contours, DEMs or viewsheds.
- Both retain a bounded copy of field overlays. Basemap caches are controlled separately and do not guarantee offline coverage.
- watchOS additionally receives the iOS phone's displayed quiet-inside perimeter. The Android reference has no matching custom perimeter store; Wear renders its ordinary tactical boundary/area graphics.
- Wear reuses Android's tactical renderer. watchOS shows native lines, areas, rings/sectors and compact typed labels; decorative control-measure details and some task/basic glyphs are simplified. See the watch README for the exact rendering limits.
