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

- animation: cards entering on launch — 91 frames at ~20fps, 5 moving (peak 93.9 levels), last movement at 1.58s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 47 frames at ~13fps, 7 moving (peak 126.9 levels), last movement at 0.52s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 35 named elements checked against a 440pt screen
- animation: scan screen pushing in — 91 frames at ~26fps, 3 moving (peak 18.1 levels), last movement at 0.15s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 37 frames at ~9fps, 7 moving (peak 7.9 levels), last movement at 3.57s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 30 frames at ~9fps, 2 moving (peak 23.7 levels), last movement at 0.35s [one step only]
- animation: review screen pushing in — at ~9fps the clip cannot resolve a transition, so the step count says nothing
- review: 56 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
- onboarding page 1: 7 named elements checked against a 440pt screen
- animation: onboarding page 1 to 2 — 5 frames at ~1fps, 2 moving (peak 16.9 levels), last movement at 2.10s [one step only]
- animation: onboarding page 1 to 2 — at ~1fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 2: Button "Skip" is 31.3x18.0pt, in the navigation bar — the bar supplies the hit area
- onboarding page 2: 8 named elements checked against a 440pt screen
- animation: onboarding page 2 to 3 — 40 frames at ~11fps, 3 moving (peak 31.6 levels), last movement at 0.35s [animated]
- onboarding page 3: 8 named elements checked against a 440pt screen
- animation: onboarding page 3 to 4 — 111 frames at ~32fps, 5 moving (peak 23.7 levels), last movement at 2.59s [animated]
- onboarding page 4: 8 named elements checked against a 440pt screen
