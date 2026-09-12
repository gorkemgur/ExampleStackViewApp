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

- animation: cards entering on launch — 168 frames at ~37fps, 25 moving (peak 76.9 levels), last movement at 3.72s [animated]
- overview: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 50 frames at ~14fps, 0 moving (peak 0.1 levels), last movement at 0.00s [static]
- live surfaces: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 66 named elements checked against a 440pt screen
- animation: scan screen pushing in — 92 frames at ~26fps, 14 moving (peak 15.5 levels), last movement at 0.72s [animated]
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 21 frames at ~5fps, 11 moving (peak 17.6 levels), last movement at 2.67s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 57 frames at ~16fps, 8 moving (peak 22.7 levels), last movement at 0.61s [animated]
- review: 42 named elements checked against a 471pt screen
- overview at accessibility text size: Button "History" is 119x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
