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
| Night mode | Local Day/Night/Follow phone choice, independent of the precision override |

Digit count describes coordinate formatting, not GPS accuracy. Both platforms display reported GPS accuracy separately. Neither companion currently promises a heading compass, haptic navigation, background tracking or navigation while the screen is locked. Those require their own platform-specific implementation and physical-device validation.

Small-screen simulator checks cover a 40 mm Apple Watch and a 192 dp round Wear OS device. Apple phone/watch application-context delivery has been exercised with a paired simulator. Wear OS rendering and freshness checks use an emulator; paired physical Data Layer delivery remains to be verified. Simulator evidence does not replace field, battery, permission or radio testing.
