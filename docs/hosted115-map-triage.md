# Hosted115 map triage — 29 October 2026

Hosted115/run40833071308 map job123311472228 is terminal failure on5b37bd2.
Artifact12883652195 SHA256
46d084fde87eee0340ce3086ea0bdc09dc8be2e8e494224200da6877ee3b63dc
verified before extraction to /tmp/mgrsgps-ci115-map. Complete main bundle has51
cases:50pass/one failure/no skips. Library115 remains active; no cancelling push.

The landscape measurement case fails before selecting a ruler: measure-distance
never appears after map-measure activation. Recording shows Terrain visibility
instead of Measurements. The helper had just dragged the short landscape rail
with a flick, returned as soon as the desired control was hittable, then tapped
its native activation point. The adjacent tool was activated. No ruler/area or
rapid-tap zoom assertion is reached; a measurement geometry defect is not shown.

Staged test repair makes the rail helper return a fully vertically visible row
and uses slow drag/hold to end momentum before release. Measurement selection
uses the existing validated-frame native helper for the rail control as well as
its menu action. Product map/drawing code, fixtures, expected point counts,
exact zoom preservation/double-tap restoration and timeout allowances unchanged.
All four local iOS26.2 measurement workflows pass with the ordinary3s moving fake
OS GPS feed: discard29.058s, landscape44.862s, area edit/undo/save/relaunch48.150s
and ruler tap/pan/reset/night36.326s. Xcode99427 finalizes TEST SUCCEEDED/exit0.
Landscape ruler/area and night ruler captures exported from the completed bundle
were inspected. The exact zoom preservation and post-drawing double-tap checks
pass. No new product map behavior is claimed. Feed30798 stopped/reaped130,
fake GPS cleared, owned phone off and cleanup62199 exit0/reaped. Ownership:
/tmp/mgrsgps-ci115-active-work.json; local result/log and exported attachments use
/tmp/mgrsgps-ci115-measurement-rail-repair* and
/tmp/mgrsgps-ci115-measurement-local-attachments/.

Evidence: /tmp/mgrsgps-ci115-map-job.log,
/tmp/mgrsgps-ci115-map-summary.json,
/tmp/mgrsgps-ci115-map-failed-landscape.png and recording
/tmp/mgrsgps-ci115-map/screenshots/ui-tests/52A51BF2-8EE9-45E2-A17A-8FC0653A6FB4.mp4.
No hosted-green claim. TAK stays off; enrolled exchange/renewal remains open.
