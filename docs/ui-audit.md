# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 77 frames at ~17fps, 5 moving (peak 81.8 levels), last movement at 0.76s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 49 frames at ~14fps, 5 moving (peak 91.5 levels), last movement at 0.43s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 105 frames at ~30fps, 3 moving (peak 20.8 levels), last movement at 0.13s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 14 frames at ~4fps, 5 moving (peak 9.9 levels), last movement at 2.00s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 20 frames at ~6fps, 5 moving (peak 22.3 levels), last movement at 1.05s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
