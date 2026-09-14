# What is left before this can go to the App Store

Everything here needs an Apple Developer account, which is why none of it is done. The
engineering side is finished and checked; what follows is account work and one decision.

## Which account, and when to buy it

**A şahıs şirketi cannot enrol as an Organization, and this is not a judgement call.** Apple's
own enrolment page says it plainly: Organization requires a D-U-N-S Number registered to a
*legal entity* — a corporation, limited partnership or LLC — and *"if your legal status is a
sole proprietorship/single person business, enrol as an individual."* DBAs, trade names and
branches are refused. A Turkish şahıs şirketi is a sole proprietorship, so Individual is the
only door.

**Individual does not limit what you can sell.** Paid apps, in-app purchases and subscriptions
are all available on an Individual account. The two differences that actually bite:

| | Individual | Organization |
|---|---|---|
| Seller name on the App Store | your legal personal name, publicly | the company's name |
| Team | one person | members with roles |

The seller name is the one worth thinking about before launch, because it is on the listing
where a buyer looks for someone to trust.

### If the business later becomes a limited şirket

That *is* a legal entity: it can get a D-U-N-S Number, enrol as an Organization, and receive the
app by transfer. Worth knowing now because two of the criteria touch this app:

- **No version may use an iCloud entitlement.** This app has none and should keep it that way —
  it is also the promise on the landing page.
- **The App Group does not block an iOS transfer**, but it has to be recreated under the new
  Team ID and the entitlements updated afterwards, or the widget silently shows nothing. That
  is the same failure the group causes when it is missing entirely, so it will look like a bug
  rather than a transfer step.
- The app must have had at least one released version, and TestFlight has to be off while the
  transfer runs.

So: enrol as an Individual now, and treat an Organization as a later migration rather than a
decision being deferred.

### When it is worth the ninety-nine dollars

Not for the engineering. A **free** Apple ID already installs on your own phone
(`docs/RUN-ON-YOUR-PHONE.md`) and answers everything §10 of `STATE-OF-PLAY.md` still wants —
including the trashing question, which needs a real folder grant rather than a paid account.

It is worth paying when either of these is true:

1. **You have decided to ship.** Everything below this section needs the account.
2. **You want to live with the app for more than a week.** Free provisioning expires after
   seven days and the app stops opening until it is re-installed. For the one thing this
   project has never had — sustained use on a real library — that weekly interruption is the
   thing most likely to stop it happening.

### Tax, in Turkey — the name of the thing to ask about

Banking and tax setup in App Store Connect, and the Paid Applications Agreement that has to be
signed before a single sale, belong to a mali müşavir and not to this document. **No figures are
written here on purpose**: they are set annually and a repository is the wrong place to keep
them fresh.

But the mechanism is worth naming, because developers routinely do not know it exists and stay
on the ordinary regime for years. **Gelir Vergisi Kanunu, mükerrer madde 20/B** — the earnings
exemption for social content creators and *mobile application developers*. In outline: for a
real person, earnings from app-store sales are exempt from income tax while they stay under the
fourth bracket ceiling of the tariff, and taxation is final through a 15% withholding taken by
the bank rather than through a return.

The conditions are the part that has to be set up *before* any money arrives, which is why this
is on the shipping list rather than in an accountant's inbox afterwards:

- an exemption certificate (*istisna belgesi*) from the tax office;
- a bank account opened specifically for this income, through which **all** of the revenue
  passes — revenue arriving anywhere else puts the exemption for that year at risk;
- Bağ-Kur (4/b) continues regardless: the exemption is from income tax, not from social
  security.

Two things specific to this project's owner are genuinely open and are the right questions to
walk in with: how the exemption interacts with an **existing şahıs şirketi**, and how VAT and
invoicing are arranged given Apple pays from abroad and is the seller to the customer.

*This is orientation, not advice. The müşavir decides.*

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
