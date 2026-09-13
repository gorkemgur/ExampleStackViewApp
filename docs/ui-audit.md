# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 75 frames at ~17fps, 4 moving (peak 84.5 levels), last movement at 0.60s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 37 frames at ~11fps, 2 moving (peak 143.3 levels), last movement at 0.28s [one step only]
- animation: live surfaces sheet presenting — at ~11fps the clip cannot resolve a transition, so the step count says nothing
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 57 frames at ~16fps, 3 moving (peak 16.2 levels), last movement at 0.25s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 12 frames at ~3fps, 2 moving (peak 12.8 levels), last movement at 1.00s [one step only]
- animation: progress card replacing the intro — at ~3fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 23 frames at ~7fps, 3 moving (peak 21.1 levels), last movement at 0.61s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
