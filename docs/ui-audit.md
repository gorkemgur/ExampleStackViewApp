# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 101 frames at ~22fps, 3 moving (peak 84.1 levels), last movement at 1.29s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 42 frames at ~12fps, 3 moving (peak 103.9 levels), last movement at 0.33s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 47 frames at ~13fps, 3 moving (peak 11.6 levels), last movement at 0.30s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 10 frames at ~2fps, 3 moving (peak 10.1 levels), last movement at 1.20s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 8 frames at ~2fps, 2 moving (peak 20.7 levels), last movement at 1.31s [one step only]
- animation: review screen pushing in — at ~2fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
