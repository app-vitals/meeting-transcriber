import SwiftUI

// MARK: - TranscriptWindowView

/// Top-level view for the transcript viewer window.
/// NavigationSplitView: sidebar (list + search) | detail (full transcript).
struct TranscriptWindowView: View {
    @ObservedObject var store: TranscriptStore

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detailContent
        }
        .onAppear {
            if store.selectedID == nil {
                store.selectedID = UserDefaults.standard.string(forKey: "lastViewedTranscriptID")
            }
        }
        .onChange(of: store.selectedID) { id in
            UserDefaults.standard.set(id, forKey: "lastViewedTranscriptID")
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            SearchBar(text: $store.searchQuery)
            Divider()
            if store.filtered.isEmpty {
                EmptyStateView(isSearching: !store.searchQuery.isEmpty)
            } else {
                List(selection: $store.selectedID) {
                    ForEach(store.filtered) { entry in
                        TranscriptRowView(entry: entry)
                            .tag(entry.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let id = store.selectedID,
           let entry = store.transcripts.first(where: { $0.id == id }) {
            TranscriptDetailView(entry: entry)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a transcript")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - SearchBar

private struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - EmptyStateView

private struct EmptyStateView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(isSearching ? "No matching transcripts" : "No transcripts yet")
                .font(.headline)
            if !isSearching {
                Text("Transcripts appear here automatically after each meeting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - TranscriptRowView

private struct TranscriptRowView: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, style: .date)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(entry.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(entry.date, style: .time)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !entry.snippet.isEmpty {
                Text(entry.snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 3)
    }
}
