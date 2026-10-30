# Route cards and strip-map PDF

Reference: Android `release/1.1.0` at `482b417`, `RouteCardDialog.kt`,
`StripMapPdf.kt` and `RouteGeometry.kt`.

Open a route in the field library. Its route card shows the eight-digit start
grid, each leg's azimuth/back-azimuth, selected distance units, pace count and
eight-digit destination grid, followed by total distance/paces, pace setting,
Zulu date-time group and reference warnings. Share route card sends the same
prepared rows as plain text.

Strip map PDF prepares a fresh report and opens a native PDF preview. Save
uses Files with a sanitized route-derived filename; Share PDF opens the system
share sheet with a named PDF file. Each share owns a temporary file so a second
share cannot overwrite one a provider is still reading.
The source route and navigation state are unchanged. Changing route geometry or
settings during preparation invalidates that result; leaving the screen or
backgrounding cancels preparation. Errors are visible and export can be retried.

The printable A4 output is black on paper white regardless of field night mode.
The first page contains a true-north-up route schematic, start/return marks,
leg numbers and an approximate metric scale. This is a schematic, not a basemap.
Reports accept routes up to the existing 250,000-vertex field-document limit;
large-container performance still needs device validation. Plot label placement
uses spatial bins and checks cancellation while processing dense imports.
The full leg table continues onto additional pages with repeated headers and
page numbers, with totals and warnings on the last page. Dense schematic labels
are omitted to avoid overlap and an explicit note reports that count; every leg
remains in the table. Very long names receive a visible request to shorten them.

Screen, text and PDF share one report calculation. Forward and reverse bearings
use their own endpoints and the selected true/magnetic/grid reference. Remote
vertex declination uses the bundled WMM or the manual override, never the
phone's current heading. Missing reference values remain UNAVAILABLE, and
expired magnetic models, polar MGRS limits and zero-length legs are explicit.
Eight-digit grid formatting is independent of the position screen's precision;
it does not promise ten-metre GPS accuracy. Route sketch longitude unwraps each
short leg at the dateline. Scale selection extends the Android candidates for
very small/large extents, preserving a readable, correctly labelled bar.

Verification includes known bearing/distance/pace fixtures, endpoint reference
conversion, unavailable/expired/manual declination, polar grids, cancellation,
dateline and degenerate sketches, multi-page/long-title/dense routes, native
PDFKit extraction and per-glyph page bounds. Actual app-renderer exports are
rasterized with Poppler and visually reviewed. UI workflows cover preview,
native Files save, route persistence and readable night controls. Physical Files
providers, sharing extensions, printing and outdoor readability still require
device checks; they are not classified as iOS limitations.

## Navigation-lane limits

The post-release Android lane extension now supplies per-leg L/R/BS landmark
summaries to the same prepared report used by the screen, shared text and PDF.
A checkpoint lane at the destination vertex wins over the route lane; hidden
lanes still apply. Linked graphics supply their current names, and missing
links are labelled as deleted. Requests capture lane/waypoint-ownership/graphic
values; changes invalidate old report/PDF preparations. Indexed ownership and
landmark lookups avoid searching and sorting the library anew for every leg.

PDF rows measure wrapped limits text before pagination. Headers repeat on
continuation pages; no limit label is silently clipped to keep a fixed row
height. Overlong unprintable labels fail with a request to shorten them. Tests
reparse actual PDFKit output, check every leg marker exactly once, keep all
character bounds inside A4, and retain one final totals section. A one-page
checkpoint-override example and the first, continuation and final pages of a
seven-page long-label example were rendered with macOS PDFKit and inspected.
