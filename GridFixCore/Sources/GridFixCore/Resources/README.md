# Model data

`WMM.COF` is the bundled WMM2025 coefficient file (epoch 2025.0). It was added
with the NOAA test-value fixture in commit `5993e76`; it is not a pending step.
`WMMValidationTests` checks the bundled model against those reference values.

See `docs/wmm-plan.md` for the original design rationale and validity-window
requirements. Refresh the coefficients and validation fixture together when
adopting a new model epoch.
