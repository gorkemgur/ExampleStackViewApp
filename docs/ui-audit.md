# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (1)

- animation: scan screen pushing in went from one screen to the next in 2 frame(s) — that is a cut, not a transition

## Measurements

- animation: cards entering on launch — 103 frames at ~23fps, 3 moving (peak 87.5 levels), last movement at 1.44s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 56 frames at ~16fps, 6 moving (peak 83.8 levels), last movement at 0.44s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 59 frames at ~17fps, 2 moving (peak 17.6 levels), last movement at 0.12s [one step only]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 11 frames at ~3fps, 1 moving (peak 18.2 levels), last movement at 0.73s [one step only]
- animation: progress card replacing the intro — at ~3fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 39 frames at ~11fps, 3 moving (peak 21.6 levels), last movement at 0.36s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
