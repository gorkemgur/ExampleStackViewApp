# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 103 frames at ~23fps, 12 moving (peak 90.2 levels), last movement at 4.24s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 48 frames at ~14fps, 6 moving (peak 136.1 levels), last movement at 0.44s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 91 frames at ~26fps, 4 moving (peak 18.8 levels), last movement at 0.19s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 14 frames at ~4fps, 4 moving (peak 11.2 levels), last movement at 1.71s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 23 frames at ~7fps, 3 moving (peak 22.2 levels), last movement at 0.61s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
