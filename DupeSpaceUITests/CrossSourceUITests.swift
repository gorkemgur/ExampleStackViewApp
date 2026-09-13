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
/// AND IT RUNS WITHOUT `-ui-testing`. Every other test in this bundle launches the app against
/// stubs; this one launches it against the real `PhotoKitMediaLibrary`, the real analyzers and
/// the real deleter, on a simulator the `real` job has already loaded with media. It is
/// excluded from the two UI shards by name — they name their suites — and named explicitly by
/// the job that has the library.
final class CrossSourceUITests: XCTestCase {

    private var app: XCUIApplication!

    /// The Files app, which owns the picker's own UI.
    private var picker: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")
    }

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
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

        // MARK: Hand the folder over

        let add = require("folders.add", in: app, timeout: 30, "no way to add a folder")
        guard add.exists else { return }
        add.tap()

        // The picker is a different process. Everything from here is Apple's UI, so it is
        // addressed by label and given room to appear.
        XCTAssertTrue(
            picker.wait(for: .runningForeground, timeout: 30),
            "the document picker never came to the front"
        )

        for step in ["Browse", "On My iPhone", folderName] {
            let target = picker.descendants(matching: .any)[step].firstMatch
            guard target.waitForExistence(timeout: 20) else {
                // Only the ones that are genuinely optional: the picker opens wherever it was
                // last, so "Browse" and "On My iPhone" may already be where we are. The folder
                // itself is not optional.
                if step == folderName {
                    XCTFail(
                        "'\(step)' was not in the picker. What it was showing:\n\n\(picker.debugDescription)"
                    )
                    return
                }
                continue
            }
            target.tap()
        }

        for label in ["Open", "Done", "Open \"\(folderName)\""] {
            let confirm = picker.buttons[label]
            if confirm.waitForExistence(timeout: 3) {
                confirm.tap()
                break
            }
        }

        // The grant lands back in the app, and the app re-reads its folders.
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "the app did not come back after the picker"
        )
        // Not `folders.message` — that identifier is the card's *failure* line ("that folder
        // could not be read", "something already covers it"), so waiting for it would have
        // passed on exactly the runs where the grant went wrong. What success looks like is a
        // row: the empty-state sentence gone, and the folder's own name on the card.
        let listed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", folderName))
            .firstMatch
        XCTAssertTrue(
            listed.waitForExistence(timeout: 30),
            "the folder was never listed on the overview, so the grant did not take. What the "
            + "app is showing:\n\n\(app.debugDescription)"
        )
        XCTAssertFalse(
            element("folders.empty", in: app).exists,
            "the folders card still says it has nothing"
        )

        // MARK: Scan, and read what it says about where each copy lives

        let scan = require("root.scan", in: app, timeout: 30, "the scan entry point was not reachable")
        guard scan.exists else { return }
        scan.tap()

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
            "the scan offered nothing at all. What is on the review screen:\n\n\(app.debugDescription)"
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
        XCTAssertTrue(
            crossed,
            "no group on the review screen said it spanned the photo library and a folder, so "
            + "nothing crossed the line the whole app is built on. Groups offered: \(rows.count)"
        )
    }
}
