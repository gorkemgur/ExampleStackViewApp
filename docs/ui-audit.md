# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (2)

- animation: cards entering on launch went from one screen to the next in 1 frame(s) — that is a cut, not a transition
- animation: scan screen pushing in never changed the screen at all

## Measurements

- animation: cards entering on launch — 71 frames at ~16fps, 1 moving (peak 90.2 levels), last movement at 0.44s [one step only]
- overview: 64 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 49 frames at ~14fps, 0 moving (peak 0.1 levels), last movement at 0.00s [static]
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 20 frames at ~5fps, 4 moving (peak 24.7 levels), last movement at 1.00s [animated]
- results: 28 named elements checked against a 440pt screen
- animation: review screen pushing in — 23 frames at ~7fps, 3 moving (peak 31.0 levels), last movement at 0.46s [animated]
- review: 47 named elements checked against a 440pt screen
- overview at accessibility text size: 64 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
