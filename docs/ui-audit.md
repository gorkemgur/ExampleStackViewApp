# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 146 frames at ~32fps, 10 moving (peak 90.2 levels), last movement at 4.32s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 55 frames at ~16fps, 7 moving (peak 122.1 levels), last movement at 0.45s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 97 frames at ~28fps, 6 moving (peak 14.1 levels), last movement at 0.29s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 15 frames at ~4fps, 5 moving (peak 10.3 levels), last movement at 2.40s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 29 frames at ~8fps, 4 moving (peak 20.9 levels), last movement at 0.60s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
