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

- animation: cards entering on launch — 122 frames at ~27fps, 4 moving (peak 88.0 levels), last movement at 4.46s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 48 frames at ~14fps, 19 moving (peak 68.7 levels), last movement at 2.41s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 35 named elements checked against a 440pt screen
- animation: scan screen pushing in — 100 frames at ~29fps, 5 moving (peak 17.2 levels), last movement at 0.21s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 39 frames at ~10fps, 7 moving (peak 7.7 levels), last movement at 3.59s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 22 frames at ~6fps, 3 moving (peak 25.4 levels), last movement at 0.64s [animated]
- review: 56 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
- onboarding page 1: 7 named elements checked against a 440pt screen
- animation: onboarding page 1 to 2 — 6 frames at ~2fps, 2 moving (peak 16.9 levels), last movement at 1.75s [one step only]
- animation: onboarding page 1 to 2 — at ~2fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 2: Button "Skip" is 31.3x18.0pt, in the navigation bar — the bar supplies the hit area
- onboarding page 2: 8 named elements checked against a 440pt screen
- animation: onboarding page 2 to 3 — 58 frames at ~17fps, 4 moving (peak 31.7 levels), last movement at 0.30s [animated]
- onboarding page 3: 8 named elements checked against a 440pt screen
- animation: onboarding page 3 to 4 — 108 frames at ~31fps, 6 moving (peak 23.1 levels), last movement at 2.53s [animated]
- onboarding page 4: 8 named elements checked against a 440pt screen
