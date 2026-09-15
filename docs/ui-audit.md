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

- animation: cards entering on launch — 85 frames at ~19fps, 5 moving (peak 87.4 levels), last movement at 4.45s [animated]
- overview: Button "History" is 100.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview: 71 named elements checked against a 440pt screen
- animation: live surfaces sheet presenting — 36 frames at ~10fps, 5 moving (peak 82.8 levels), last movement at 0.58s [animated]
- live surfaces: Button "Close" is 67.0x36.0pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 45 named elements checked against a 440pt screen
- animation: scan screen pushing in — 104 frames at ~30fps, 4 moving (peak 19.6 levels), last movement at 0.17s [animated]
- scan: 21 named elements checked against a 440pt screen
- animation: progress card replacing the intro — 26 frames at ~6fps, 8 moving (peak 8.0 levels), last movement at 2.77s [animated]
- results: 35 named elements checked against a 440pt screen
- animation: review screen pushing in — not measured (no frame reader on this machine)
- review: 46 named elements checked against a 440pt screen
- overview at accessibility text size: Button "History" is 119.0x36.0pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 71 named elements checked against a 440pt screen
- large text: the scan screen was never reached, only the overview audited
- onboarding page 1: 7 named elements checked against a 440pt screen
- animation: onboarding page 1 to 2 — 5 frames at ~1fps, 2 moving (peak 15.8 levels), last movement at 2.10s [one step only]
- animation: onboarding page 1 to 2 — at ~1fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 2: Button "Skip" is 31.3x18.0pt, in the navigation bar — the bar supplies the hit area
- onboarding page 2: 8 named elements checked against a 440pt screen
- animation: onboarding page 2 to 3 — 48 frames at ~14fps, 1 moving (peak 26.3 levels), last movement at 0.15s [one step only]
- animation: onboarding page 2 to 3 — at ~14fps the clip cannot resolve a transition, so the step count says nothing
- onboarding page 3: 8 named elements checked against a 440pt screen
- animation: onboarding page 3 to 4 — 29 frames at ~8fps, 5 moving (peak 24.7 levels), last movement at 2.66s [animated]
- onboarding page 4: 8 named elements checked against a 440pt screen
