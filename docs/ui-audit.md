# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (3)

- review: Button "Biggest" is 66x44pt, under the 44pt tap target
- review: Button "Oldest" is 58x44pt, under the 44pt tap target
- review: Button "Newest" is 63x44pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 77 frames at ~17fps, 3 moving (peak 87.0 levels), last movement at 0.64s [animated]
- overview: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 35 frames at ~10fps, 2 moving (peak 123.0 levels), last movement at 0.30s [one step only]
- animation: live surfaces sheet presenting — at ~10fps the clip cannot resolve a transition, so the step count says nothing
- live surfaces: Button "Close" is 67x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 53 frames at ~15fps, 4 moving (peak 16.3 levels), last movement at 0.33s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 9 frames at ~2fps, 3 moving (peak 11.1 levels), last movement at 2.22s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 24 frames at ~7fps, 3 moving (peak 22.2 levels), last movement at 0.58s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
