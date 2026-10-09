import SwiftUI

struct SessionsListView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        List {
            ForEach(store.sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    SessionRow(session: session)
                }
            }
            .onDelete { store.delete(atOffsets: $0) }
        }
        .overlay {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Sync your device to download recordings.")
                )
            }
        }
        .toolbar {
            if !store.sessions.isEmpty {
                EditButton()
            }
        }
        .navigationTitle("Recordings")
    }
}

private struct SessionRow: View {
    let session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startDate, format: .dateTime.weekday().month().day().hour().minute())
                .font(.headline)
            HStack(spacing: 16) {
                Label(formatDuration(session.duration), systemImage: "clock")
                if let avg = session.averageHR {
                    Label("\(avg) bpm avg", systemImage: "heart.fill")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
}

#Preview {
    NavigationStack {
        SessionsListView()
    }
    .previewEnvironment()
}
