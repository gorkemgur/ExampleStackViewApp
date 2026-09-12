# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 136 frames at ~30fps, 10 moving (peak 96.8 levels), last movement at 4.10s [animated]
- overview: 64 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 88 frames at ~25fps, 4 moving (peak 56.7 levels), last movement at 0.16s [animated]
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 21 frames at ~5fps, 9 moving (peak 14.6 levels), last movement at 2.29s [animated]
- results: 28 named elements checked against a 440pt screen
- animation: review screen pushing in — 52 frames at ~15fps, 8 moving (peak 29.8 levels), last movement at 0.54s [animated]
- review: 47 named elements checked against a 440pt screen
- overview at accessibility text size: 64 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
