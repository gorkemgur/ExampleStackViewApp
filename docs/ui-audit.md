# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 182 frames at ~40fps, 19 moving (peak 76.9 levels), last movement at 3.41s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 55 frames at ~16fps, 14 moving (peak 64.7 levels), last movement at 1.08s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 98 frames at ~28fps, 8 moving (peak 17.3 levels), last movement at 0.32s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 15 frames at ~4fps, 3 moving (peak 12.1 levels), last movement at 1.60s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 38 frames at ~11fps, 7 moving (peak 14.3 levels), last movement at 0.74s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
