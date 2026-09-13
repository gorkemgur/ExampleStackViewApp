# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (1)

- animation: scan screen pushing in never changed the screen at all

## Measurements

- animation: cards entering on launch — 108 frames at ~24fps, 6 moving (peak 90.2 levels), last movement at 4.38s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 40 frames at ~11fps, 5 moving (peak 91.7 levels), last movement at 0.53s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 47 frames at ~13fps, 0 moving (peak 0.1 levels), last movement at 0.00s [static]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 11 frames at ~3fps, 2 moving (peak 17.4 levels), last movement at 1.45s [one step only]
- animation: progress card replacing the intro — at ~3fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 35 frames at ~10fps, 4 moving (peak 21.0 levels), last movement at 0.50s [animated]
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
