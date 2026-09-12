# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (9)

- animation: live surfaces sheet presenting never changed the screen at all
- animation: scan screen pushing in went from one screen to the next in 2 frame(s) — that is a cut, not a transition
- animation: progress card replacing the intro went from one screen to the next in 1 frame(s) — that is a cut, not a transition
- review: Button "Everything, 6 items" is 162x34pt, under the 44pt tap target
- review: Button "Photos, 4 items" is 140x34pt, under the 44pt tap target
- review: Button "Videos, 2 items" is 138x34pt, under the 44pt tap target
- review: Button "Biggest" is 66x32pt, under the 44pt tap target
- review: Button "Oldest" is 58x32pt, under the 44pt tap target
- review: Button "Newest" is 63x32pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 103 frames at ~23fps, 5 moving (peak 63.8 levels), last movement at 1.66s [animated]
- overview: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 45 frames at ~13fps, 0 moving (peak 0.2 levels), last movement at 0.00s [static]
- live surfaces: Button "History" is 100x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 66 named elements checked against a 440pt screen
- animation: scan screen pushing in — 73 frames at ~21fps, 2 moving (peak 59.1 levels), last movement at 0.10s [one step only]
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 16 frames at ~4fps, 1 moving (peak 42.6 levels), last movement at 0.50s [one step only]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 24 frames at ~7fps, 5 moving (peak 40.6 levels), last movement at 0.73s [animated]
- review: 46 named elements checked against a 471pt screen
- overview at accessibility text size: Button "History" is 119x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
