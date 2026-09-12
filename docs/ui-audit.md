# UI audit

Layout is measured from the accessibility tree; animation from a burst of
screenshots. See `Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (11)

- animation: cards entering on launch never changed the screen at all
- overview: Button "Live surfaces" is 125x36pt, under the 44pt tap target
- animation: live surfaces sheet presenting never changed the screen at all
- live surfaces: Button "Close" is 67x36pt, under the 44pt tap target
- animation: scan screen pushing in never changed the screen at all
- animation: progress card replacing the intro never changed the screen at all
- animation: review screen pushing in never changed the screen at all
- review: Button "Deselect all" is 81x34pt, under the 44pt tap target
- review: Button "Deselect all" is 81x34pt, under the 44pt tap target
- overview at accessibility text size: Button "Live surfaces" is 144x36pt, under the 44pt tap target
- scan at accessibility text size: Button "Live surfaces" is 144x36pt, under the 44pt tap target

## Measurements

- animation: cards entering on launch — 2 frames sampled over 8.5s, 0 change(s), settled at 0.0s [static]
- overview: 65 named elements checked against a 375pt screen
- animation: live surfaces sheet presenting — 1 frames sampled over 2.9s, 0 change(s), settled at 0.0s [static]
- live surfaces: 22 named elements checked against a 375pt screen
- animation: scan screen pushing in — 1 frames sampled over 2.5s, 0 change(s), settled at 0.0s [static]
- scan: 7 named elements checked against a 375pt screen
- animation: progress card replacing the intro — 2 frames sampled over 2.6s, 0 change(s), settled at 0.0s [static]
- results: 25 named elements checked against a 375pt screen
- animation: review screen pushing in — 1 frames sampled over 2.1s, 0 change(s), settled at 0.0s [static]
- review: 23 named elements checked against a 375pt screen
- overview at accessibility text size: 65 named elements checked against a 375pt screen
- scan at accessibility text size: 65 named elements checked against a 375pt screen
