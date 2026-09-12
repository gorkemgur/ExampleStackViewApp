# What is left before this can go to the App Store

Everything here needs an Apple Developer account, which is why none of it is done. The
engineering side is finished and checked; what follows is account work and one decision.

## Already in place

| | |
|---|---|
| `PrivacyInfo.xcprivacy` | Declares no tracking, no collected data, and the three accessed-API reasons: file timestamps (`C617.1`), disk space (`E174.1`), user defaults (`CA92.1`). Nothing leaves the device, so there is nothing to declare as collected. |
| `NSPhotoLibraryUsageDescription` | Written in the app's own words rather than boilerplate. |
| App group | `group.com.gorkemgur.dupespace`, shared by the app and the widget extension. |
| App icon | 1024×1024 in the asset catalogue. |
| Live Activities | `NSSupportsLiveActivities` set; frequent updates off, because the scan reports on its own schedule. |
| Release signing | The app and the widget sign automatically in Release. This was broken until recently — `CODE_SIGNING_ALLOWED: NO` sat in the *base* settings for CI's benefit, which meant a signed archive was impossible and nothing in the pipeline would ever have caught it, because nothing archives. It is Debug-only now, and CI builds Release on every push. |

## What you have to do

1. **Team and bundle identifier.** `com.gorkemgur.dupespace` and `com.gorkemgur.dupespace.widgets`
   are placeholders. Register both on your account, then add `DEVELOPMENT_TEAM` to
   `project.yml`.
2. **The app group has to be registered too** — the widget reads what the app writes through
   it, so a missing group is a widget that silently shows nothing.
3. **Archive**: `xcodebuild archive -scheme DupeSpace -configuration Release`, then Organizer.
4. **App Privacy answers in App Store Connect.** They are all "no": no data collected, no data
   linked to the user, no tracking. The manifest already says so; the questionnaire is
   separate and has to agree with it.
5. **Review notes.** Say plainly that the app deletes photos through `PHPhotoLibrary`, which
   puts Apple's own confirmation in front of every deletion and sends items to Recently
   Deleted. A reviewer who does not know that will assume the worst of a cleaner app.

## The one decision that is not paperwork

**Files-folder deletions are immediate and permanent.** Photos get Recently Deleted; a file in
a granted folder does not. The app says so in three places and offers to export originals
first — but you should decide whether to ship the folder feature in version one at all, or
hold it until there has been a round of real-world use on the photo half, where a mistake is
recoverable for thirty days.
