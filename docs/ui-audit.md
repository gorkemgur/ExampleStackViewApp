# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 168 frames at ~37fps, 21 moving (peak 76.8 levels), last movement at 3.75s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 86 frames at ~25fps, 5 moving (peak 19.5 levels), last movement at 0.28s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 19 frames at ~5fps, 2 moving (peak 12.6 levels), last movement at 0.84s [one step only]
- animation: progress card replacing the intro — at ~5fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 29 frames at ~8fps, 1 moving (peak 23.9 levels), last movement at 0.24s [one step only]
- animation: review screen pushing in — at ~8fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
