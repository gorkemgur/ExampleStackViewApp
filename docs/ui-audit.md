# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (4)

- animation: scan screen pushing in went from one screen to the next in 1 frame(s) — that is a cut, not a transition
- review: Button "Biggest" is 66x44pt, under the 44pt tap target
- review: Button "Oldest" is 58x44pt, under the 44pt tap target
- review: Button "Newest" is 63x44pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 52 frames at ~12fps, 1 moving (peak 13.4 levels), last movement at 0.09s [one step only]
- animation: cards entering on launch — at ~12fps the clip cannot resolve a transition, so the step count says nothing
- overview: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 39 frames at ~11fps, 8 moving (peak 79.6 levels), last movement at 0.81s [animated]
- live surfaces: Button "Close" is 67x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 95 frames at ~27fps, 1 moving (peak 49.9 levels), last movement at 0.04s [one step only]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 22 frames at ~6fps, 11 moving (peak 40.2 levels), last movement at 2.91s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 44 frames at ~13fps, 4 moving (peak 35.5 levels), last movement at 0.48s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
