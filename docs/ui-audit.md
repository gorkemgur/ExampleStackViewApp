# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (1)

- animation: scan screen pushing in never changed the screen at all

## Measurements

- animation: cards entering on launch — 82 frames at ~18fps, 4 moving (peak 90.2 levels), last movement at 4.45s [animated]
- overview: 66 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 67 frames at ~19fps, 0 moving (peak 0.6 levels), last movement at 0.00s [static]
- scan: 9 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 34 frames at ~8fps, 6 moving (peak 26.0 levels), last movement at 1.76s [animated]
- results: 28 named elements checked against a 440pt screen
- animation: review screen pushing in — 43 frames at ~12fps, 3 moving (peak 36.8 levels), last movement at 0.24s [animated]
- review: 45 named elements checked against a 440pt screen
- overview at accessibility text size: 66 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
