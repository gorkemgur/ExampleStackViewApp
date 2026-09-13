# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 204 frames at ~45fps, 19 moving (peak 76.7 levels), last movement at 3.26s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 79 frames at ~23fps, 5 moving (peak 19.5 levels), last movement at 0.31s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 15 frames at ~4fps, 5 moving (peak 9.7 levels), last movement at 1.87s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 28 frames at ~8fps, 4 moving (peak 21.0 levels), last movement at 0.62s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
