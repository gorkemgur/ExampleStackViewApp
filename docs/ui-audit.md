# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (7)

- animation: scan screen pushing in never changed the screen at all
- scan: Button "Strict" is 123x34pt, under the 44pt tap target
- scan: Button "Balanced" is 123x34pt, under the 44pt tap target
- scan: Button "Loose" is 123x34pt, under the 44pt tap target
- review: Button "No loss" is 123x34pt, under the 44pt tap target
- review: Button "+ bursts" is 123x34pt, under the 44pt tap target
- review: Button "+ similar" is 123x34pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — not measured (no frame reader on this machine)
- overview: 64 named elements checked against a 440pt screen
- live surfaces: no entry point found, skipped
- animation: scan screen pushing in — 24 frames at ~7fps, 0 moving (peak 0.1 levels), last movement at 0.00s [static]
- scan: 11 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 28 frames at ~7fps, 7 moving (peak 18.7 levels), last movement at 2.00s [animated]
- results: 28 named elements checked against a 440pt screen
- animation: review screen pushing in — 30 frames at ~9fps, 4 moving (peak 30.6 levels), last movement at 0.47s [animated]
- review: 47 named elements checked against a 440pt screen
- overview at accessibility text size: 64 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
