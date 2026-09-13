# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (2)

- animation: cards entering on launch went from one screen to the next in 2 frame(s) — that is a cut, not a transition
- animation: scan screen pushing in went from one screen to the next in 2 frame(s) — that is a cut, not a transition

## Measurements

- animation: cards entering on launch — 71 frames at ~16fps, 2 moving (peak 86.5 levels), last movement at 0.44s [one step only]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 36 frames at ~10fps, 5 moving (peak 94.6 levels), last movement at 0.58s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 81 frames at ~23fps, 2 moving (peak 14.2 levels), last movement at 0.09s [one step only]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 11 frames at ~3fps, 1 moving (peak 18.2 levels), last movement at 0.73s [one step only]
- animation: progress card replacing the intro — at ~3fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 31 frames at ~9fps, 8 moving (peak 18.0 levels), last movement at 1.02s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
