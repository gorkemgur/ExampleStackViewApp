# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 153 frames at ~34fps, 10 moving (peak 90.2 levels), last movement at 3.85s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 66 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — not measured (no frame reader on this machine)
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 12 frames at ~3fps, 2 moving (peak 16.8 levels), last movement at 1.67s [one step only]
- animation: progress card replacing the intro — at ~3fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 20 frames at ~6fps, 2 moving (peak 23.3 levels), last movement at 0.53s [one step only]
- animation: review screen pushing in — at ~6fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
