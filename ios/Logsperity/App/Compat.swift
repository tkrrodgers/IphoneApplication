import LogsperityCore
import SwiftUI

// Small wrappers for iPhone-only modifiers, so the app's views also type-check on macOS (ios/AppCheck).

enum KeyboardKind { case decimal, number, phone, email, name }

extension View {
    @ViewBuilder func keyboard(_ kind: KeyboardKind) -> some View {
        #if os(iOS)
        switch kind {
        case .decimal: keyboardType(.decimalPad)
        case .number: keyboardType(.numberPad)
        case .phone: keyboardType(.phonePad).textContentType(.telephoneNumber)
        case .email: keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .name: textInputAutocapitalization(.words)
        }
        #else
        self
        #endif
    }

    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var formBottom: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }
}

extension Color {
    /// Logsperity brand (design §15.1).
    static let brandBlue = Color(red: 0x2B / 255, green: 0x5D / 255, blue: 0xA8 / 255)
    static let brandGold = Color(red: 0xF9 / 255, green: 0xC4 / 255, blue: 0x6B / 255)
    static let profitTeal = Color(red: 0x3F / 255, green: 0xB8 / 255, blue: 0xAE / 255)
    static let expenseOrange = Color(red: 0xF7 / 255, green: 0xA3 / 255, blue: 0x5C / 255)

    init(hex: String) {
        let v = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension Day {
    /// Bridges to SwiftUI's DatePicker.
    var asDate: Date { date() }
}

extension Binding where Value == Day {
    var asDate: Binding<Date> {
        Binding<Date>(get: { wrappedValue.date() }, set: { wrappedValue = Day(date: $0) })
    }
}

extension Binding where Value == String? {
    /// Treats nil as "" for text fields, and "" as nil when saving.
    var orEmpty: Binding<String> {
        Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
