# UI audit

Layout is measured from the accessibility tree; animation from a burst of
screenshots. See `Scripts/audit-ui.py` for what each number can and cannot say.

## Findings (0)

- Nothing overflowed, nothing was untappable, nothing failed to move.

## Measurements

- animation: cards entering on launch — not measured (no ffmpeg on this machine)
- overview: Button "Live surfaces" is 125x36pt, in the navigation bar — the bar supplies the hit area
- overview: 65 named elements checked against a 375pt screen
- animation: live surfaces sheet presenting — not measured (no ffmpeg on this machine)
- live surfaces: Button "Close" is 67x36pt, in the navigation bar — the bar supplies the hit area
- live surfaces: 22 named elements checked against a 375pt screen
- animation: scan screen pushing in — not measured (no ffmpeg on this machine)
- scan: 7 named elements checked against a 375pt screen
- animation: progress card replacing the intro — not measured (no ffmpeg on this machine)
- results: 25 named elements checked against a 375pt screen
- animation: review screen pushing in — not measured (no ffmpeg on this machine)
- review: 22 named elements checked against a 375pt screen
- overview at accessibility text size: Button "Live surfaces" is 144x36pt, in the navigation bar — the bar supplies the hit area
- overview at accessibility text size: 65 named elements checked against a 375pt screen
- large text: the tap on the scan entry did not land, overview audited twice
