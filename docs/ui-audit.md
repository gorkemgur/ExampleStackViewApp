# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (1)

- animation: scan screen pushing in went from one screen to the next in 2 frame(s) — that is a cut, not a transition

## Measurements

- animation: cards entering on launch — 137 frames at ~30fps, 11 moving (peak 79.8 levels), last movement at 4.47s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 59 frames at ~17fps, 11 moving (peak 87.8 levels), last movement at 0.71s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 63 frames at ~18fps, 2 moving (peak 9.9 levels), last movement at 0.17s [one step only]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 12 frames at ~3fps, 3 moving (peak 16.3 levels), last movement at 1.67s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 22 frames at ~6fps, 4 moving (peak 23.6 levels), last movement at 0.80s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
