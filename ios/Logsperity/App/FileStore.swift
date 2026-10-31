import Foundation
import LogsperityCore

/// Saves the log book and settings as JSON in Application Support, protected while the phone is locked.
/// The pilot keeps data on the phone only; the developer receives nothing (design §6.1 rule 6).
struct FileStore {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logsperity", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    var bookURL: URL { directory.appendingPathComponent("logbook.json") }
    var settingsURL: URL { directory.appendingPathComponent("settings.json") }

    func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    func loadBook() -> LogBook? { load(LogBook.self, from: bookURL) }
    func loadSettings() -> AppSettings? { load(AppSettings.self, from: settingsURL) }
    func saveBook(_ book: LogBook) throws { try save(book, to: bookURL) }
    func saveSettings(_ settings: AppSettings) throws { try save(settings, to: settingsURL) }

    /// A readable copy of everything, for "Export my data".
    func exportURL(book: LogBook) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Logsperity data.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(book).write(to: url, options: .atomic)
        return url
    }
}
