# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — not measured (no frame reader on this machine)
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 42 frames at ~12fps, 2 moving (peak 146.5 levels), last movement at 0.17s [one step only]
- animation: live surfaces sheet presenting — at ~12fps the clip cannot resolve a transition, so the step count says nothing
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — only 1 frames recorded, inconclusive
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 10 frames at ~2fps, 1 moving (peak 18.0 levels), last movement at 1.60s [one step only]
- animation: progress card replacing the intro — at ~2fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 8 frames at ~2fps, 2 moving (peak 20.6 levels), last movement at 1.31s [one step only]
- animation: review screen pushing in — at ~2fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
