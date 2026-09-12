# Running it on your own phone

Everything below assumes a Mac with Xcode and the phone on a cable. It takes about five
minutes, and you do not need a paid Apple Developer membership.

## With a free Apple ID

```sh
brew install xcodegen          # once
./Scripts/for-my-phone.sh com.yourname
open DupeSpace.xcodeproj
```

Then, in Xcode: select the **DupeSpace** target → *Signing & Capabilities* → **Team**, and pick
your own Apple ID. Do the same for **DupeSpaceWidgets**. Choose your phone in the scheme
selector and press Run.

The first launch will stop with *Untrusted Developer*. On the phone: **Settings → General →
VPN & Device Management → your Apple ID → Trust**.

A free team's provisioning lasts **seven days**. When the app stops opening, press Run again.

### What the script changes, and why

| | Why a free account cannot have it |
|---|---|
| The App Group is removed | Only the widgets use it, and a personal team cannot create one at all. Xcode refuses to sign a build that asks for one. |
| The bundle identifiers are re-prefixed | `com.gorkemgur.*` belongs to somebody. Apple hands each identifier to one account. |

Nothing the app *does* changes. Scan, compare, budget, delete and the receipt are untouched.
The widgets install and run, and show their "nothing yet" state: without the group,
`SharedContainer.snapshotStore()` returns `nil`, and every caller already draws a placeholder
rather than inventing numbers.

`project.personal.yml` is generated and git-ignored. Run `xcodegen` on its own to go back to
the real project.

## With a paid membership

Skip the script. Open the project as it is, register `com.gorkemgur.dupespace`,
`com.gorkemgur.dupespace.widgets` and the App Group `group.com.gorkemgur.dupespace` under your
team, set **Team** on both targets, and Run. The widgets then carry real numbers, and the
provisioning does not expire after a week. `docs/SHIPPING.md` covers the rest of what
distribution needs.

## What to look at first, with a real library

The simulator walk runs against a twenty-eight item fixture, which is exactly the wrong size to
find anything interesting. On a real phone, the things worth pointing a camera at:

- **The scan screen before you press Start.** It now states what it will open: how many of each
  kind, how many are read, how many are iCloud-only and never touched. Check the count against
  what Settings says the library holds.
- **A library with nothing to find.** Every screen has an empty state and they are the least
  exercised part of the app. The review screen with no candidates, the budget card with a
  ceiling of zero, the widgets before the first scan.
- **Cloud-only originals.** If most of the library is Optimise-iPhone-Storage, the scan will set
  most of it aside — and the honesty card on the overview is the only place that says so.
- **The regret ladder's top two rungs.** Identical and re-send are the pre-ticked ones. Open a
  few and check the app kept the copy you would have kept.
- **Recently Deleted.** After a deletion, the photos should be in that album, and the space
  should not come back until it is emptied. The receipt says so; check that it is true.

Nothing is deleted without a second confirmation, and the photo half goes to Recently Deleted
for thirty days. Files in a folder you granted do not: those go immediately.
