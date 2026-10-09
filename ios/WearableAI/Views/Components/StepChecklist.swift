import SwiftUI

/// A row in a progress checklist: done (green check), in progress (spinner), or pending.
struct ChecklistRow: View {
    enum Status {
        case pending, active, done
    }

    let title: String
    let status: Status

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch status {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .active:
                    ProgressView()
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
            .frame(width: 24)

            Text(title)
                .foregroundStyle(status == .pending ? .secondary : .primary)
        }
    }
}

/// A Dropbox-style badge (not the real logo).
struct CloudBadge: View {
    var body: some View {
        Image(systemName: "shippingbox.fill")
            .font(.system(size: 48))
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

extension Int64 {
    var fileSizeText: String { formatted(.byteCount(style: .file)) }
}
