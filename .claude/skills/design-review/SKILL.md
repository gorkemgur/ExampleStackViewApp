---
name: design-review
description: Run the full measured design review — render the landing page in a real browser and the app on a simulator, measure layout and motion, then report defects. Use after any visual change, or when a screen looks wrong and you want the reason.
---

# Design review

Three passes. Each produces evidence, not an opinion.

## 1. The page, measured in a browser
```bash
python3 Scripts/check-site.py docs/index.html
```
catches missing assets, anything loaded from a third party, absolute paths, missing alt text and a
missing reduced-motion block.

Then render it. Chromium is at `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`; pass it as
`executablePath`. At 1440, 768, 390 and 320 points, in both colour schemes, check no horizontal
overflow, no console errors, and that two frames 400ms apart differ where something should be
moving. Repeat with `reducedMotion: 'reduce'` and confirm nothing is animating and nothing is left
faded.

## 2. The app, measured on a simulator
CI does this on a macOS runner — there is no simulator in this container. `Scripts/audit-ui.py`
runs there and writes `docs/ui-audit.md`:
- every element's frame against the screen, so overflow and small tap targets are arithmetic;
- a screen recording across each transition, read frame by frame, so "it animates" is measured
  rather than assumed;
- a second pass at an accessibility text size.

Read `docs/ui-audit.md` after a run. A finding there is a fact.

## 3. The eye
Read `docs/screenshots/*.png` — the Read tool renders them. Look for what no assertion catches:
"1 items", a number cut in half, a claim the screen cannot support, two designs of the same app
side by side. Every defect in this project that mattered was found this way.

## Reporting
Most severe first, `file:line`, one sentence on the defect, one on the fix. If a screenshot is
older than the code, say so before drawing conclusions from it — a stale capture has been the
wrong answer here more than once.
