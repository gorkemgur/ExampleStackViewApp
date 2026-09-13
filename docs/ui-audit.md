# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 111 frames at ~25fps, 8 moving (peak 76.7 levels), last movement at 1.30s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 49 frames at ~14fps, 5 moving (peak 126.3 levels), last movement at 0.36s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 64 frames at ~18fps, 3 moving (peak 10.7 levels), last movement at 0.22s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 10 frames at ~2fps, 4 moving (peak 10.8 levels), last movement at 2.40s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 25 frames at ~7fps, 4 moving (peak 21.1 levels), last movement at 0.70s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
