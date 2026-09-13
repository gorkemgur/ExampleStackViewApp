# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 128 frames at ~28fps, 7 moving (peak 90.2 levels), last movement at 3.80s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 33 frames at ~9fps, 6 moving (peak 108.7 levels), last movement at 0.64s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 45 frames at ~13fps, 3 moving (peak 20.1 levels), last movement at 0.31s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 15 frames at ~4fps, 5 moving (peak 7.5 levels), last movement at 1.87s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 23 frames at ~7fps, 2 moving (peak 25.4 levels), last movement at 0.30s [one step only]
- animation: review screen pushing in — at ~7fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
