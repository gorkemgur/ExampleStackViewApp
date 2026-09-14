# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (1)

- animation: scan screen pushing in went from one screen to the next in 2 frame(s) — that is a cut, not a transition

## Measurements

- animation: cards entering on launch — 158 frames at ~35fps, 11 moving (peak 82.0 levels), last movement at 3.62s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 46 frames at ~13fps, 10 moving (peak 110.8 levels), last movement at 1.14s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 99 frames at ~28fps, 2 moving (peak 14.8 levels), last movement at 0.11s [one step only]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 11 frames at ~3fps, 3 moving (peak 13.1 levels), last movement at 1.82s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 23 frames at ~7fps, 4 moving (peak 19.7 levels), last movement at 0.76s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
