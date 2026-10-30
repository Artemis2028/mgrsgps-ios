# Hosted run125: random-course feed race

Field artifact12952344907 matched931866171bytes and SHA256 `52612db36ef676bb7838f6f126d8c73dac886e0dd50d0bb4a65431b0bc83fc6f`. Download44546/extraction87862 exited zero/reaped. Finalized initialUI428total418passed0failed10skipped; expiry/recovery1passed, course/speed1passed, boundary5passed, navigation1passed. The post-build cached execution path has positive hosted confirmation. Practice15total14passed1failed.

The sole practice failure, random checkpoint write/retry/relaunch at night (20.609s), observed CP2 of5 immediately after retry while expecting CP1. The external fake OS GPS route alternates points approximately122m apart every15s. Random checkpoints start at least120m from their creation origin, so subsequent route movement can legitimately reach CP1. The storage/relaunch test's fixed-progress expectation needs a stationary location rather than an uncontrolled arrival.

Random setup and random checkpoint day/night retry tests now use the existing tokenized PRACTICE_SPLITS_HOLD/RELEASE host controls. The app still receives actual simulator Core Location callbacks. No production arrival/scoring change, weaker assertion, injected fix, fixture reduction or increased deadline. Movement/completion workflows keep advancing the external route.

Fresh iPhone16e/iOS26.2 native validation: day retry52.379s, night retry48.022s, random setup8.363s, completion while viewing splits34.209s, advancing course/summary42.055s. Five tests/zero failures. Result `/tmp/mgrsgps-ci125-practice-local.xcresult`; log `/tmp/mgrsgps-ci125-practice-local.log`. Day/night reopened CP1 and final live-splits captures inspected. Setup69293/test59524/cleanup48772 exited zero/reaped. The test parent killed/reaped its own external feed and cleared fake GPS; only disposable285ABE29-A0DE-4C0A-8FC9-7D36D0A7EEF0 was shut down/deleted. User watch preview retained.

CI125 map passed; library failed and needs artifact triage before combined follow-up. Full hosted validation remains open. Current enrolled TAK exchange/renewal/native Renew UI and physical gates remain open; TAK stays off. No merge, publish or release.
