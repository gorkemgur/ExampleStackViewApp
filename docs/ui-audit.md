# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (3)

- review: Button "Biggest" is 66x44pt, under the 44pt tap target
- review: Button "Oldest" is 58x44pt, under the 44pt tap target
- review: Button "Newest" is 63x44pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 170 frames at ~38fps, 18 moving (peak 76.7 levels), last movement at 3.73s [animated]
- overview: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 117 frames at ~33fps, 4 moving (peak 66.4 levels), last movement at 0.12s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 19 frames at ~5fps, 6 moving (peak 96.3 levels), last movement at 1.89s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 51 frames at ~15fps, 1 moving (peak 38.8 levels), last movement at 0.07s [one step only]
- animation: review screen pushing in — at ~15fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
