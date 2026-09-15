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

- animation: cards entering on launch — 83 frames at ~18fps, 7 moving (peak 76.7 levels), last movement at 4.39s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 42 frames at ~12fps, 6 moving (peak 99.2 levels), last movement at 0.67s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 35 named elements checked against a 440pt screen
- animation: scan screen pushing in — 47 frames at ~13fps, 3 moving (peak 19.3 levels), last movement at 0.30s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 32 frames at ~8fps, 5 moving (peak 9.9 levels), last movement at 3.50s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 20 frames at ~6fps, 1 moving (peak 23.5 levels), last movement at 0.17s [one step only]
- animation: review screen pushing in — at ~6fps the clip cannot resolve a transition, so the step count says nothing
- review: 56 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
- onboarding page 1: 7 named elements checked against a 440pt screen
- animation: onboarding page 1 to 2 — 19 frames at ~5fps, 1 moving (peak 14.4 levels), last movement at 0.74s [one step only]
- animation: onboarding page 1 to 2 — at ~5fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 2: Button "Skip" is 31.3x18.0pt, in the navigation bar — the bar supplies the hit area
- onboarding page 2: 8 named elements checked against a 440pt screen
- animation: onboarding page 2 to 3 — 27 frames at ~8fps, 3 moving (peak 28.9 levels), last movement at 0.52s [animated]
- onboarding page 3: 8 named elements checked against a 440pt screen
- animation: onboarding page 3 to 4 — 50 frames at ~14fps, 7 moving (peak 22.8 levels), last movement at 2.73s [animated]
- onboarding page 4: 8 named elements checked against a 440pt screen
