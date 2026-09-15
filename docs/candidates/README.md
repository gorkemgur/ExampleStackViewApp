# What the search for a sweeping figure actually turned up

Nothing usable, and the honest version is short.

**unDraw** — 1,740 illustrations, MIT, free for commercial use. **Not one of them holds a
broom.** The nearest are `clean-up` (a figure clearing tiles into a bin), `throw-away` (a
figure dropping a document into a bin) and `painting-the-room` (a roller on a pole, which is
at least the right posture). I recoloured eight of them to this app's palette, looked at
them, and they were all rejected — correctly, none of them is a person cleaning. They have
been removed rather than left here to be scrolled past.

**Everything animated is unreachable from this environment.** LottieFiles, IconScout,
lottie.host and svgrepo all answer 403 at the network proxy on CONNECT, so no Lottie JSON or
animated GIF could be fetched. I am not going to describe files I have not opened. Only
`registry.npmjs.org` and `raw.githubusercontent.com` are reachable, which is how the unDraw
set was obtained at all.

## The part that matters more than the licence

A flat illustration could not do this job even if one existed. They are single poses with no
rig: nothing in the file separates the arm from the body, so a figure can be made to bob or
float, but it cannot sweep. Using one means giving up the movement, which is the whole thing
that was asked for.

`DupeSpace/Sources/Components/SweeperRingView.swift` draws its own for that reason — a Canvas and
about a dozen paths. The legs alternate, the body bobs, the broom swings more than twice as
wide as the shoulders sway, and the figure's position along the floor is the real progress
reading.

## If you want a downloaded one anyway

Download a Lottie yourself and drop the JSON in this folder; I will wire it up. LottieFiles'
public animations carry the Lottie Simple License, which clears commercial use with no
attribution. Worth knowing first: it means shipping the `lottie-ios` dependency, the figure
stops being tied to the real progress count, and the app gains an asset whose licence has to
be tracked.
