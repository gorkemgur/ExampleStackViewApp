# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 133 frames at ~30fps, 11 moving (peak 76.9 levels), last movement at 3.92s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 51 frames at ~15fps, 19 moving (peak 60.6 levels), last movement at 1.85s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 103 frames at ~29fps, 6 moving (peak 16.9 levels), last movement at 0.27s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 15 frames at ~4fps, 4 moving (peak 11.7 levels), last movement at 2.13s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 18 frames at ~5fps, 7 moving (peak 16.3 levels), last movement at 1.56s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
