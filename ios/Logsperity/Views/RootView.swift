import SwiftUI

/// Tabs: Today · Log · Reports · Coach · More (design §7). HERB is reachable from every tab.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = "today"
    @State private var showHerb = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: "today") { TodayView(showHerb: $showHerb) }
            Tab("Log", systemImage: "square.and.pencil", value: "log") { LogHomeView() }
            Tab("Reports", systemImage: "chart.bar.doc.horizontal", value: "reports") { ReportsMenuView() }
            Tab("Coach", systemImage: "figure.mind.and.body", value: "coach") { CoachView() }
            Tab("More", systemImage: "ellipsis.circle", value: "more") { MoreView() }
        }
        .sheet(isPresented: $showHerb) { HerbView() }
        .modifier(OnboardingCover(isPresented: !model.settings.onboarded))
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }
}

private struct OnboardingCover: ViewModifier {
    let isPresented: Bool
    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: .constant(isPresented)) { OnboardingView() }
        #else
        content.sheet(isPresented: .constant(isPresented)) { OnboardingView() }
        #endif
    }
}

/// The floating "Ask HERB" button shown on Today.
struct AskHerbButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Ask HERB", systemImage: "waveform.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(.capsule)
        .accessibilityHint("Talk or type to log entries and ask about your numbers")
    }
}
