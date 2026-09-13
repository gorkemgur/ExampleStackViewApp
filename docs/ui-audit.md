# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 96 frames at ~21fps, 6 moving (peak 74.5 levels), last movement at 4.41s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 46 frames at ~13fps, 10 moving (peak 84.9 levels), last movement at 0.84s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 95 frames at ~27fps, 3 moving (peak 19.0 levels), last movement at 0.15s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 11 frames at ~3fps, 3 moving (peak 15.6 levels), last movement at 2.55s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 23 frames at ~7fps, 4 moving (peak 22.3 levels), last movement at 0.76s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
