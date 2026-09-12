# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (4)

- animation: cards entering on launch went from one screen to the next in 2 frame(s) — that is a cut, not a transition
- review: Button "Biggest" is 66x44pt, under the 44pt tap target
- review: Button "Oldest" is 58x44pt, under the 44pt tap target
- review: Button "Newest" is 63x44pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 154 frames at ~34fps, 2 moving (peak 88.6 levels), last movement at 0.85s [one step only]
- overview: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 48 frames at ~14fps, 14 moving (peak 91.5 levels), last movement at 1.53s [animated]
- live surfaces: Button "Close" is 67x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 92 frames at ~26fps, 4 moving (peak 46.7 levels), last movement at 0.15s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 19 frames at ~5fps, 10 moving (peak 46.1 levels), last movement at 2.74s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 38 frames at ~11fps, 1 moving (peak 38.9 levels), last movement at 0.09s [one step only]
- animation: review screen pushing in — at ~11fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
