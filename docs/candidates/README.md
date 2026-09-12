# Candidates for the deletion animation

Put here to be looked at and then kept or deleted. Nothing in this folder is wired into the
app — `DupeSpace/Sources/Views/SweeperRingView.swift` still draws its own figure.

## What could actually be found

**unDraw** — the eight SVGs in `undraw/`. Free for commercial use, no attribution required;
the npm package they came from (`undraw-svg` 2.0.0) is MIT. Pulled from the npm registry
because `undraw.co` itself is blocked by this environment's network policy.

They are recoloured to this app's palette, so they can be judged against the real screen
rather than against unDraw's stock purple and pink: their accent to `#0A6FE0`, the limb tone
to `#7FC4FF`, their two darks to the slab's `#1E3145` / `#18293C`.

| File | What it shows |
|---|---|
| `clean-up.svg` | A figure clearing tiles off a wall into a bin. The closest thing in the library to "someone tidying". |
| `throw-away.svg` | A figure dropping a document into a bin. The most literal match for what this screen does. |
| `schedule-cleanup.svg` | A figure beside a calendar, papers falling. |
| `organize-photos.svg` | Two figures and a phone full of pictures. On-theme for the app rather than for the moment. |
| `duplicate.svg` | A figure beside a copy-of-a-card. Exactly this app's subject. |
| `memory-storage.svg` | A figure among documents. |
| `photos.svg` | A figure behind a stack of photographs. |
| `selecting.svg` | A figure choosing between three things. |

## What could not be found, and why

**No animated candidates.** Everything above is static. LottieFiles, IconScout, lottie.host
and svgrepo are all refused by the network policy here (403 at the proxy on CONNECT), so no
Lottie JSON or animated GIF could be fetched and I am not going to describe files I have not
opened. If you want a Lottie, the workable route is you downloading one and dropping it in —
LottieFiles' public animations carry the Lottie Simple License, which clears commercial use
without attribution.

**No sweeping figure at all.** unDraw has 1,740 illustrations and not one of them holds a
broom. `clean-up` and `throw-away` are the nearest, and neither is sweeping.

## What is honestly wrong with all of them

They are flat marketing illustrations: one pose, no rig, drawn at roughly a quarter of a
screen. The moment asks for something the size of a control that moves while work happens.
An unDraw figure can be made to bob or float, but its arm cannot sweep — nothing in the file
separates the arm from the body. So using one means giving up the part you asked for, which
is the movement.

They also sit inside a ring badly. They are wide compositions with props and foliage, and
cropping one to a circle throws most of it away.

The hand-drawn figure in `SweeperRingView` exists because of exactly that: it is rigged, so
its broom swings, its legs alternate, and its position along the floor is the real progress
reading. It costs no licence and no download.
