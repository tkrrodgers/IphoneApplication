import LogsperityCore
import SwiftUI

/// Ask HERB (S19). Placeholder until the conversation engine is wired in.
struct HerbView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("HERB is on the way", systemImage: "waveform")
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}
