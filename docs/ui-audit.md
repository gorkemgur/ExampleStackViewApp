# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (7)

- animation: scan screen pushing in went from one screen to the next in 2 frame(s) — that is a cut, not a transition
- onboarding page 1: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 2: Button "Back" is 35.3x18.0pt, under the 44pt tap target
- onboarding page 3: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 3: Button "Back" is 35.3x18.0pt, under the 44pt tap target
- onboarding page 4: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 4: Button "Back" is 35.3x18.0pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 149 frames at ~33fps, 6 moving (peak 90.2 levels), last movement at 3.87s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 26 frames at ~7fps, 1 moving (peak 139.0 levels), last movement at 0.27s [one step only]
- animation: live surfaces sheet presenting — at ~7fps the clip cannot resolve a transition, so the step count says nothing
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 35 named elements checked against a 440pt screen
- animation: scan screen pushing in — 90 frames at ~26fps, 2 moving (peak 14.3 levels), last movement at 0.12s [one step only]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 35 frames at ~9fps, 6 moving (peak 6.3 levels), last movement at 3.54s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 29 frames at ~8fps, 2 moving (peak 24.7 levels), last movement at 0.48s [one step only]
- animation: review screen pushing in — at ~8fps the clip cannot resolve a transition, so the step count says nothing
- review: 56 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
- onboarding page 1: 7 named elements checked against a 440pt screen
- animation: onboarding page 1 to 2 — 5 frames at ~1fps, 2 moving (peak 20.4 levels), last movement at 2.10s [one step only]
- animation: onboarding page 1 to 2 — at ~1fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 2: Button "Skip" is 31.3x18.0pt, in the navigation bar — the bar supplies the hit area
- onboarding page 2: 8 named elements checked against a 440pt screen
- animation: onboarding page 2 to 3 — 45 frames at ~13fps, 3 moving (peak 30.6 levels), last movement at 0.31s [animated]
- onboarding page 3: 8 named elements checked against a 440pt screen
- animation: onboarding page 3 to 4 — 70 frames at ~20fps, 6 moving (peak 23.8 levels), last movement at 2.65s [animated]
- onboarding page 4: 8 named elements checked against a 440pt screen
