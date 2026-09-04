# Model data

`WMM.COF` belongs here and is deliberately **not** committed until it has been
downloaded from the source rather than typed from anywhere.

    curl -O https://www.ncei.noaa.gov/products/world-magnetic-model  # see docs/wmm-plan.md

Until it is present, `WMM.bundled` is nil and the app falls back to the
declination iOS derives from `CLHeading`. That fallback only works for here and
now with the compass running, which is why the file matters.
