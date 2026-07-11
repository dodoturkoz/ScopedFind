import SwiftUI
import AppKit

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.filename)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(result.parentDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }
}

