import SwiftUI
import UIKit

/// The permission gate.
///
/// Limited access gets its own copy rather than being lumped in with denial: the app *is*
/// allowed to read something, it just cannot answer the question the user is asking, and
/// saying so plainly is more useful than a generic "grant access" wall.
struct AccessCardView: View {

    let access: LibraryAccess
    let onRequest: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.title)
                    .foregroundStyle(.tint)

                Text(headline)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("access.headline")

                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("access.button")
        }
    }

    private var symbolName: String {
        switch access {
        case .notDetermined: return "photo.on.rectangle.angled"
        case .limited: return "eye.trianglebadge.exclamationmark"
        case .denied, .restricted: return "lock"
        case .authorized: return "checkmark.circle"
        }
    }

    private var headline: String {
        switch access {
        case .notDetermined: return "Let DupeSpace see your library"
        case .limited: return "Limited access is not enough"
        case .denied: return "Photo access is off"
        case .restricted: return "Photo access is restricted"
        case .authorized: return "Ready"
        }
    }

    private var explanation: String {
        switch access {
        case .notDetermined:
            return "Finding duplicates means comparing every photo against every other one, so the whole library has to be readable. Nothing leaves the device and nothing is uploaded."
        case .limited:
            return "You picked individual photos. Duplicates only exist relative to the rest of the library, so a hand-picked subset cannot be checked. Switch to full access in Settings."
        case .denied:
            return "Turn photo access on in Settings to scan for duplicates and see what they cost you."
        case .restricted:
            return "A device policy blocks photo access, so the library cannot be scanned."
        case .authorized:
            return ""
        }
    }

    private var buttonTitle: String {
        access == .notDetermined ? "Allow access" : "Open Settings"
    }

    private func action() {
        guard access != .notDetermined else {
            onRequest()
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
