import Foundation
import Observation

/// Saves recorded sessions on the phone, one JSON file per session in Documents/Sessions.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [RecordingSession] = []

    @ObservationIgnored private let directory: URL

    private static let seededKey = "didSeedSampleSessions"

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.documentsDirectory.appending(path: "Sessions", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        load()

        // Add some example sessions on first launch so the Sessions tab isn't empty.
        if sessions.isEmpty && !UserDefaults.standard.bool(forKey: Self.seededKey) {
            generateSampleSessions()
            UserDefaults.standard.set(true, forKey: Self.seededKey)
        }
    }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(RecordingSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startDate > $1.startDate }
    }

    func save(_ session: RecordingSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(session)
            try data.write(to: fileURL(for: session), options: .atomic)
        } catch {
            print("Failed to save session \(session.id): \(error)")
        }
        sessions.append(session)
        sessions.sort { $0.startDate > $1.startDate }
    }

    func delete(_ session: RecordingSession) {
        try? FileManager.default.removeItem(at: fileURL(for: session))
        sessions.removeAll { $0.id == session.id }
    }

    func delete(atOffsets offsets: IndexSet) {
        for session in offsets.map({ sessions[$0] }) {
            delete(session)
        }
    }

    func deleteAll() {
        for session in sessions {
            delete(session)
        }
    }

    /// Adds a few fake sessions from the past few days.
    func generateSampleSessions(count: Int = 3) {
        for day in 1...count {
            let start = Calendar.current.date(byAdding: .day, value: -day, to: .now)!
            let duration = TimeInterval.random(in: 180...360)
            save(SyntheticSessionFactory.makeSession(start: start, duration: duration))
        }
    }

    private func fileURL(for session: RecordingSession) -> URL {
        directory.appending(path: "\(session.id.uuidString).json")
    }
}
