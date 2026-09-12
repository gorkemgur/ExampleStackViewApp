# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (1)

- animation: cards entering on launch went from one screen to the next in 2 frame(s) — that is a cut, not a transition

## Measurements

- animation: cards entering on launch — 22 frames at ~5fps, 2 moving (peak 55.7 levels), last movement at 2.45s [one step only]
- overview: 64 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — only 1 frames recorded, inconclusive
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 20 frames at ~5fps, 5 moving (peak 25.1 levels), last movement at 1.40s [animated]
- results: 28 named elements checked against a 440pt screen
- animation: review screen pushing in — 44 frames at ~13fps, 3 moving (peak 33.7 levels), last movement at 0.24s [animated]
- review: 45 named elements checked against a 440pt screen
- overview at accessibility text size: 64 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
