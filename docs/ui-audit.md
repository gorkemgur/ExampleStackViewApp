# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 95 frames at ~21fps, 5 moving (peak 76.8 levels), last movement at 0.76s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 45 frames at ~13fps, 6 moving (peak 133.7 levels), last movement at 0.47s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 99 frames at ~28fps, 4 moving (peak 18.8 levels), last movement at 0.18s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 13 frames at ~3fps, 3 moving (peak 12.8 levels), last movement at 1.85s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 22 frames at ~6fps, 5 moving (peak 21.0 levels), last movement at 0.95s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
