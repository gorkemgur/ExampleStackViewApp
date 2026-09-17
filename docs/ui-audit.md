# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (6)

- onboarding page 1: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 2: Button "Back" is 35.3x18.0pt, under the 44pt tap target
- onboarding page 3: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 3: Button "Back" is 35.3x18.0pt, under the 44pt tap target
- onboarding page 4: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 4: Button "Back" is 35.3x18.0pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 103 frames at ~23fps, 4 moving (peak 82.0 levels), last movement at 1.09s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 41 frames at ~12fps, 10 moving (peak 124.0 levels), last movement at 0.94s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 35 named elements checked against a 440pt screen
- animation: scan screen pushing in — 83 frames at ~24fps, 5 moving (peak 18.2 levels), last movement at 0.25s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 34 frames at ~8fps, 3 moving (peak 14.4 levels), last movement at 2.47s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 27 frames at ~8fps, 3 moving (peak 23.7 levels), last movement at 0.52s [animated]
- review: 56 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
- onboarding page 1: 7 named elements checked against a 440pt screen
- animation: onboarding page 1 to 2 — 70 frames at ~20fps, 4 moving (peak 30.4 levels), last movement at 0.25s [animated]
- onboarding page 2: Button "Skip" is 31.3x18.0pt, in the navigation bar — the bar supplies the hit area
- onboarding page 2: 8 named elements checked against a 440pt screen
- animation: onboarding page 2 to 3 — 43 frames at ~12fps, 2 moving (peak 27.8 levels), last movement at 0.24s [one step only]
- animation: onboarding page 2 to 3 — at ~12fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 3: 8 named elements checked against a 440pt screen
- animation: onboarding page 3 to 4 — 45 frames at ~13fps, 1 moving (peak 30.0 levels), last movement at 3.19s [one step only]
- animation: onboarding page 3 to 4 — at ~13fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 4: 8 named elements checked against a 440pt screen
