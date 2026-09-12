# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (3)

- review: Button "Everything, 6 items" is 162x34pt, under the 44pt tap target
- review: Button "Photos, 4 items" is 140x34pt, under the 44pt tap target
- review: Button "Videos, 2 items" is 138x34pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 176 frames at ~39fps, 12 moving (peak 95.8 levels), last movement at 2.66s [animated]
- overview: 64 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 89 frames at ~25fps, 10 moving (peak 50.4 levels), last movement at 0.67s [animated]
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 20 frames at ~5fps, 8 moving (peak 23.4 levels), last movement at 2.40s [animated]
- results: 28 named elements checked against a 440pt screen
- animation: review screen pushing in — 49 frames at ~14fps, 12 moving (peak 17.2 levels), last movement at 1.29s [animated]
- review: 42 named elements checked against a 471pt screen
- overview at accessibility text size: 64 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
