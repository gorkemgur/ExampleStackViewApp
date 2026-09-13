import XCTest

/// The same picture in the photo library and in a folder the user handed over — proven, at last,
/// against the real thing.
///
/// This is the app's one distinctive claim. Apple's Duplicates looks inside the photo library
/// and stops at its edge; a file browser cannot see inside it at all. So the photograph you
/// exported to Files once is invisible to both, and it is the duplicate people are most certain
/// they do not have.
///
/// WHY IT IS HERE AND NOT IN THE idb DRIVER. `real-library-check.py` can put a populated folder
/// on the device — writing into the Files app's own container works — but it cannot hand that
/// folder over, because `UIDocumentPickerViewController` is hosted out of process and
/// `idb describe-all` returns only the application under test. The tree at the failing step was
/// one line long:
///
///     --- what was on the screen at looking for 'Browse' in the picker: 1 elements
///         Application: id=None label='DupeSpace'
///
/// XCUITest can reach system UI by bundle identifier, which idb cannot. So the placement stays
/// in the Python driver and the granting moves here.
///
/// WHICH PROCESS OWNS THE PICKER IS NOT ASSUMED. It is found by looking — see `findPicker()`.
///
/// AND IT RUNS WITHOUT `-ui-testing`. Every other test in this bundle launches the app against
/// stubs; this one launches it against the real `PhotoKitMediaLibrary`, the real analyzers and
/// the real deleter, on a simulator the `real` job has already loaded with media. It is
/// excluded from the two UI shards by name — they name their suites — and named explicitly by
/// the job that has the library.
final class CrossSourceUITests: XCTestCase {

    private var app: XCUIApplication!

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// Every process the document picker might be living in, named so a failure can say which
    /// one it looked in.
    ///
    /// The app itself is first and is not a formality. `UIDocumentPickerViewController` is a
    /// remote view controller, but a remote view's accessibility tree is bridged into its
    /// *host* — so on some iOS versions the picker's elements answer to the app's own query
    /// and the separate process is never foregrounded at all. Run 148 asserted
    /// `com.apple.DocumentManagerUICore` came to the front and waited thirty seconds for
    /// something that may never have been going to happen.
    private var pickerHosts: [(name: String, app: XCUIApplication)] {
        [
            ("the app's own tree", app),
            ("com.apple.DocumentManagerUICore", XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")),
            ("com.apple.DocumentsApp", XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")),
            ("com.apple.springboard", springboard),
        ]
    }

    /// Labels that only a document picker has. `folders.add` is the last thing tapped before
    /// this runs, and none of these is on the overview behind it.
    private let pickerMarks = ["Browse", "Recents", "On My iPhone", "Shared", "Cancel"]

    /// Find the picker by looking for it, rather than by believing a bundle identifier.
    ///
    /// - Returns: the process it was found in, or `nil` — in which case every candidate's tree
    ///   has already been printed, because a failure here that cannot say what *was* on the
    ///   screen costs a full CI round trip to learn one fact.
    private func findPicker(timeout: TimeInterval = 30) -> (name: String, app: XCUIApplication)? {
        // One query per host per pass, not one per label. `.exists` takes a fresh snapshot of
        // that process's whole accessibility tree every time it is asked, so five labels across
        // four processes would be twenty snapshots a pass — which is how a poll turns into the
        // thing it was waiting for.
        let anyMark = NSPredicate(format: "label IN %@", pickerMarks)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for host in pickerHosts {
                let mark = host.app.descendants(matching: .any).matching(anyMark).firstMatch
                if mark.exists {
                    print("the picker is in \(host.name) — found it by '\(mark.label)'")
                    return host
                }
            }
        }

        for host in pickerHosts {
            print("""

            ===== \(host.name), state \(host.app.state.rawValue) =====
            \(screen(host.app))
            """)
        }
        return nil
    }

    /// The folder `place_the_folder()` writes into the Files app's container.
    private let folderName = "DupeSpace Fixture"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // No `-ui-testing`: this is the real path or it is nothing.
        app.launchArguments = []
        app.launch()
    }

    /// Answer whatever the system puts up, without caring which wording this iOS chose.
    ///
    /// `simctl privacy grant photos` exits 0 and iOS asks anyway — the Python driver learned
    /// that days ago and taps through it. The same is true here, and `addUIInterruptionMonitor`
    /// is unreliable for a dialog that is already on screen when the test starts, so this looks
    /// for the button itself.
    private func answerSystemPrompt(_ labels: [String], timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let button = springboard.buttons[label]
                if button.exists && button.isHittable {
                    button.tap()
                    return true
                }
            }
            _ = springboard.buttons.firstMatch.waitForExistence(timeout: 1)
        }
        return false
    }

    func testAPictureInBothHalvesIsFoundAndSaidToBeInBoth() {
        _ = answerSystemPrompt(["Allow Full Access", "Allow Access to All Photos", "Allow"])

        require("storage.headline", in: app, timeout: 120, "the app never got past launch")

        // MARK: The permission, actually granted

        // Belt and braces for the thing that made run 154 read a short library. The job grants
        // photo access with `simctl` before this runs, but a grant is only as good as the app
        // being installed when it is made, and a reinstall or a fresh container can lose it.
        // Rather than trust it, look: the app draws this card whenever access is anything other
        // than authorised, and a scan run behind it compares a fraction of the library and
        // offers a fraction of the groups — which looks like a matcher fault and is not one.
        if element("access.headline", in: app).exists {
            let ask = element("access.button", in: app)
            if ask.exists { ask.tap() }
            _ = answerSystemPrompt(
                ["Allow Full Access", "Allow Access to All Photos", "Allow"], timeout: 25
            )
        }
        let wall = element("access.headline", in: app).exists
        print("the permission wall is \(wall ? "still up — the library will be short" : "down")")

        // MARK: Hand the folder over

        let add = require("folders.add", in: app, timeout: 30, "no way to add a folder")
        guard add.exists else { return }
        add.tap()

        // Everything from here is Apple's UI. Which process it lives in is found, not assumed
        // — and run 149 answered it: the app's own tree. `UIDocumentPickerViewController` is a
        // remote view controller, but a remote view's accessibility tree is bridged into its
        // host, so the picker's elements answer to `XCUIApplication()` and no second process
        // is ever foregrounded.
        guard let host = findPicker() else {
            XCTFail("no document picker appeared anywhere after tapping Add a folder — every tree above")
            return
        }
        let hostName = host.name
        let picker = host.app

        // The tab bar, by its own identifier. Not `picker.buttons["Browse"]`: run 149's tree
        // has two elements labelled Browse — the tab and the navigation bar's back button —
        // and `firstMatch` on that is a coin toss between going forward and going back.
        let tabs = picker.tabBars["DOC.browsingModeTabBar"]
        if tabs.buttons["Browse"].waitForExistence(timeout: 20) {
            tabs.buttons["Browse"].tap()
        }

        // And the files themselves, inside the picker's own collection. The picker is in the
        // app's tree, so an unscoped query for a folder name would happily match the app's own
        // chrome behind the sheet.
        let files = picker.collectionViews["File View"]
        XCTAssertTrue(
            files.waitForExistence(timeout: 20),
            "the picker never showed a file list (\(hostName)):\n\n\(screen(picker))"
        )

        for step in ["On My iPhone", folderName] {
            let target = files.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ OR label == %@", step, step))
                .firstMatch
            guard target.waitForExistence(timeout: 20) else {
                // "On My iPhone" is optional — the picker reopens wherever it was last, so it
                // may already be inside it. The fixture folder is not.
                if step != folderName { continue }

                // The failure that matters, named rather than left to be read out of a
                // thousand-line tree. Run 149 ended exactly here, and the reason was on the
                // screen: the folder had been written into the Files app's data container,
                // and "On My iPhone" is served by `com.apple.FileProvider.LocalStorage`.
                let empty = picker.staticTexts
                    .matching(NSPredicate(format: "label CONTAINS[c] 'is Empty'"))
                    .firstMatch
                if empty.exists {
                    XCTFail(
                        "the picker says '\(empty.label)' — the fixture was not written where "
                        + "this location is served from. See `local_storage_directories()`."
                    )
                } else {
                    XCTFail(
                        "'\(step)' was not in the picker (\(hostName)). What it was showing:"
                        + "\n\n\(screen(picker))"
                    )
                }
                return
            }
            // The cell, not whatever descendant the query happened to resolve first. In icon
            // mode a folder's label is a `StaticText` sitting under the icon, and run 152
            // tapped one of those to no effect at all: the element existed, the tap was
            // synthesised, and the picker did not move. Tapping the row is what the picker
            // listens to.
            let cell = files.cells.containing(
                NSPredicate(format: "label == %@ OR identifier == %@", step, step)
            ).firstMatch
            (cell.exists ? cell : target).tap()
        }

        // MARK: Commit, wherever the taps have left us

        // Open grants *the directory you are standing in*, and a tap on a folder may navigate
        // into it, may only select it, or — as run 153 discovered on the second tap — may be
        // read as the choice itself and close the picker there and then.
        //
        // All three are fine. `FileMediaLibrary` enumerates without
        // `.skipsSubdirectoryDescendants`, so a grant on the fixture or on its parent both
        // contain the fixture's files. So this stops trying to steer and just reports where it
        // ended up.
        let bar = picker.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        let arrived = bar.staticTexts.matching(NSPredicate(format: "label == %@", folderName)).firstMatch

        if !arrived.waitForExistence(timeout: 15) {
            // Some pickers read one tap on a folder as selecting it and want a second to go in.
            let cell = files.cells.containing(
                NSPredicate(format: "label == %@ OR identifier == %@", folderName, folderName)
            ).firstMatch
            if cell.exists { cell.doubleTap() }
            _ = arrived.waitForExistence(timeout: 10)
        }

        // Never `firstMatch.label` on a query that may be empty: reading a property off no
        // match throws, and run 153 was destroyed by its own diagnostic doing exactly that —
        // the picker had already closed, so the navigation bar it was asking about was gone.
        // A line printed to explain a failure must not be able to cause one.
        let title = bar.staticTexts.firstMatch
        print("the picker is showing '\(title.exists ? title.label : "nothing — it has closed")'")

        // Only if it is still open. If the tap already chose the folder, there is nothing left
        // to commit and pressing on would tap whatever is now underneath.
        if bar.exists {
            let open = bar.buttons["Open"]
            if open.waitForExistence(timeout: 10) {
                open.tap()
            } else {
                for label in ["Open", "Done"] where picker.buttons[label].exists {
                    picker.buttons[label].tap()
                    break
                }
            }
        }

        // MARK: Wait for the picker to actually be gone

        // Because the picker is inside the app's own tree, and for as long as it is dismissing
        // its breadcrumb still carries the folder's name. Run 150 searched the whole app for
        // that name, matched the sheet that was still on screen, concluded the folder was
        // listed on the overview, and then failed one line later on a card that had not been
        // given the grant yet. A query that cannot tell the sheet from the screen behind it is
        // not evidence about either.
        if files.exists {
            let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: files)
            guard XCTWaiter().wait(for: [dismissed], timeout: 30) == .completed else {
                XCTFail("the picker never went away after Open — the grant was never committed")
                return
            }
        }

        // MARK: And then read the card

        // Not `folders.message` — that identifier is the card's *failure* line ("that folder
        // could not be read", "something already covers it"), so waiting for it would have
        // passed on exactly the runs where the grant went wrong. What success looks like is the
        // empty-state sentence going away.
        let empty = element("folders.empty", in: app)
        if empty.exists {
            let filled = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: empty)
            guard XCTWaiter().wait(for: [filled], timeout: 30) == .completed else {
                // The two outcomes need different answers, and the app says which: it sets
                // `folders.message` when it refuses a grant and leaves it nil when it takes one.
                let message = element("folders.message", in: app)
                XCTFail(
                    message.exists
                        ? "the app refused the folder: \(message.label)"
                        : "the folders card still says it has nothing, and gave no reason:"
                          + "\n\n\(screen(app))"
                )
                return
            }
        }

        require(
            "folders.title", in: app, timeout: 10,
            "the folders card went missing after the grant"
        )
        // A row, by the control that only a row has. Not by the folder's name: the grant may
        // be on the fixture or on its parent, and both are correct as far as this test is
        // concerned — the scan below is what has to come out right.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "folders.remove."))
            .firstMatch
        guard row.waitForExistence(timeout: 20) else {
            // The card's own rows, rather than the whole application. Run 151 answered a
            // question like this one with a two-thousand-line tree in which the single line
            // that mattered sat in the middle, and reading it cost a round trip of its own.
            let title = element("folders.title", in: app)
            let add = element("folders.add", in: app)
            let rows = app.staticTexts.allElementsBoundByIndex
                .filter { $0.frame.minY > title.frame.maxY && $0.frame.maxY < add.frame.minY }
                .map { $0.label }
            XCTFail("the card stopped saying it was empty but carries no folder. It shows: \(rows)")
            return
        }

        // MARK: Scan, and read what it says about where each copy lives

        let scan = require("root.scan", in: app, timeout: 30, "the scan entry point was not reachable")
        guard scan.exists else { return }
        scan.tap()

        // Read the ledger before starting, and keep it.
        //
        // This screen states how many items are indexed and how many will actually be opened,
        // and that number is the one thing that separates the two ways this test can fail:
        // either the granted folder's three files are not in the scan at all — a grant or an
        // enumeration problem — or they are, and the matcher did not pair them across the line
        // — a threshold problem. Run 154 failed at the very end with "Groups offered: 2", which
        // is exactly the library's own byte-identical pairs, and could not say which of the two
        // it was. Guessing between them costs a run either way, so it is carried to the
        // failure instead.
        let plan = element("scan.plan.summary", in: app)
        let ledger = plan.waitForExistence(timeout: 30) ? plan.label : "(the plan never appeared)"
        print("the scan is about to run: \(ledger)")

        let start = require("scan.start", in: app, timeout: 30, "the scan screen did not open")
        guard start.exists else { return }
        start.tap()

        let review = require("scan.review", in: app, timeout: 300, "the scan never finished")
        guard review.exists else { return }
        review.tap()

        require("review.total", in: app, timeout: 30, "the review screen did not open")

        // MARK: Find the group that crosses the line, and make it say so

        // Not by hunting for the filename on the list: the row shows the *keeper's* name, and
        // which half of a crossing pair wins is the ranker's decision, not something a test
        // should presume. So open the groups and ask each one.
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.open."))
        XCTAssertTrue(
            rows.firstMatch.waitForExistence(timeout: 60),
            "the scan offered nothing at all. What is on the review screen:\n\n\(screen(app))"
        )

        var crossed = false
        // Capped: the fixture builds nine groups at the outside, and a walk that would open
        // eighty is a hang dressed up as a search.
        let limit = min(rows.count, 20)
        for index in 0 ..< limit {
            let row = rows.element(boundBy: index)
            guard row.exists, row.isHittable else { continue }
            row.tap()

            // Short: the detail screen is already built by the time it is on screen.
            if element("group.spansSources", in: app).waitForExistence(timeout: 4) {
                crossed = true
                break
            }

            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 10) else {
                XCTFail("could not get back out of a group")
                return
            }
            back.tap()
            _ = rows.firstMatch.waitForExistence(timeout: 10)
        }

        // Both halves of the claim in one assertion, because either alone is worth nothing: a
        // crossing pair that is never found means the app cannot do the one thing no other
        // cleaner does, and a crossing pair found but never announced means the person has no
        // reason to believe it looked anywhere their own eyes had not.
        if !crossed {
            // What was offered, by name, and what the scan had to work with. Between them these
            // say which half is broken without anybody having to run it again.
            let offered = (0 ..< min(rows.count, 20))
                .map { rows.element(boundBy: $0) }
                .filter { $0.exists }
                .map { $0.label }
            let fromTheFolder = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] 'exported-'"))
                .firstMatch
                .exists

            XCTFail(
                """
                no group said it spanned the photo library and a folder, so nothing crossed the \
                line the whole app is built on.

                the scan's own ledger:   \(ledger)
                groups offered:          \(rows.count) — \(offered)
                anything named exported- on the review screen: \(fromTheFolder)
                the permission wall was \(wall ? "UP — the library itself was short" : "down")

                If the ledger counts the folder's three files and nothing named exported- is \
                offered, the files were read and the matcher did not pair them: a threshold \
                question. If the ledger does not count them, the grant is not reaching \
                `FileMediaLibrary` and the matcher is innocent.
                """
            )
        }
    }
}
