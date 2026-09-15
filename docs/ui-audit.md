# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (7)

- onboarding page 1: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 2: Button "Back" is 35.3x18.0pt, under the 44pt tap target
- animation: onboarding page 2 to 3 went from one screen to the next in 2 frame(s) — that is a cut, not a transition
- onboarding page 3: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 3: Button "Back" is 35.3x18.0pt, under the 44pt tap target
- onboarding page 4: Button "Skip" is 31.3x18.0pt, under the 44pt tap target
- onboarding page 4: Button "Back" is 35.3x18.0pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 121 frames at ~27fps, 8 moving (peak 90.2 levels), last movement at 4.39s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 34 frames at ~10fps, 2 moving (peak 146.0 levels), last movement at 0.21s [one step only]
- animation: live surfaces sheet presenting — at ~10fps the clip cannot resolve a transition, so the step count says nothing
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 78 frames at ~22fps, 3 moving (peak 18.7 levels), last movement at 0.13s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 12 frames at ~3fps, 1 moving (peak 17.4 levels), last movement at 1.00s [one step only]
- animation: progress card replacing the intro — at ~3fps the clip cannot resolve a transition, so the step count says nothing
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — 25 frames at ~7fps, 2 moving (peak 23.0 levels), last movement at 0.42s [one step only]
- animation: review screen pushing in — at ~7fps the clip cannot resolve a transition, so the step count says nothing
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
- onboarding page 1: 7 named elements checked against a 440pt screen
- animation: onboarding page 1 to 2 — 47 frames at ~13fps, 5 moving (peak 27.8 levels), last movement at 0.52s [animated]
- onboarding page 2: Button "Skip" is 31.3x18.0pt, in the navigation bar — the bar supplies the hit area
- onboarding page 2: 8 named elements checked against a 440pt screen
- animation: onboarding page 2 to 3 — 53 frames at ~15fps, 2 moving (peak 28.7 levels), last movement at 0.20s [one step only]
- onboarding page 3: 8 named elements checked against a 440pt screen
- animation: onboarding page 3 to 4 — 61 frames at ~17fps, 3 moving (peak 22.6 levels), last movement at 2.24s [animated]
- onboarding page 4: 8 named elements checked against a 440pt screen
