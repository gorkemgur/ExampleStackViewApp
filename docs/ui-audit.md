# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (4)

- animation: live surfaces sheet presenting never changed the screen at all
- review: Button "Everything, 6 items" is 162x34pt, under the 44pt tap target
- review: Button "Photos, 4 items" is 140x34pt, under the 44pt tap target
- review: Button "Videos, 2 items" is 138x34pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 110 frames at ~24fps, 3 moving (peak 87.5 levels), last movement at 1.39s [animated]
- overview: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 49 frames at ~14fps, 0 moving (peak 0.1 levels), last movement at 0.00s [static]
- live surfaces: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 66 named elements checked against a 440pt screen
- animation: scan screen pushing in — 90 frames at ~26fps, 3 moving (peak 74.0 levels), last movement at 0.12s [animated]
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 22 frames at ~6fps, 10 moving (peak 16.0 levels), last movement at 2.55s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 47 frames at ~13fps, 3 moving (peak 39.6 levels), last movement at 0.22s [animated]
- review: 42 named elements checked against a 471pt screen
- overview at accessibility text size: Button "History" is 119x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
