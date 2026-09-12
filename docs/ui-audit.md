# UI audit

Layout is measured from the accessibility tree; animation from a screen
recording taken across each transition and read frame by frame. See
`Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — 142 frames at ~32fps, 115 differing, movement ends at 4.47s [animated]
- overview: Button "Live surfaces" is 125x36pt, in the navigation bar — the bar supplies the hit area
- overview: 65 named elements checked against a 375pt screen
- animation: live surfaces sheet presenting — 115 frames at ~33fps, 94 differing, movement ends at 3.47s [animated]
- live surfaces: Button "Close" is 67x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 22 named elements checked against a 375pt screen
- animation: scan screen pushing in — 105 frames at ~30fps, 85 differing, movement ends at 3.47s [animated]
- scan: 7 named elements checked against a 375pt screen
- animation: progress card replacing the intro — 46 frames at ~12fps, 45 differing, movement ends at 3.91s [animated]
- results: 25 named elements checked against a 375pt screen
- animation: review screen pushing in — 78 frames at ~22fps, 77 differing, movement ends at 3.46s [animated]
- review: 22 named elements checked against a 375pt screen
- overview at accessibility text size: Button "Live surfaces" is 144x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 65 named elements checked against a 375pt screen
- large text: the scan screen was never reached, only the overview audited
