import SwiftUI

// MARK: - TranscriptWindowView

/// Top-level view for the transcript viewer window.
/// NavigationSplitView: sidebar (list + search + filters) | detail (full transcript).
struct TranscriptWindowView: View {
    @ObservedObject var store: TranscriptStore

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
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
            FilterBar(store: store)
            Divider()
            if store.filtered.isEmpty {
                EmptyStateView(isSearching: !store.searchQuery.isEmpty || store.hasActiveFilters)
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

// MARK: - TranscriptStore filter helpers

extension TranscriptStore {
    var hasActiveFilters: Bool {
        dateFilter != .all || hasActionItemsOnly || !searchQuery.isEmpty
    }
}

// MARK: - SearchBar

private struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search transcripts", text: $text)
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

// MARK: - FilterBar

private struct FilterBar: View {
    @ObservedObject var store: TranscriptStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                // Date range filter
                Picker("", selection: $store.dateFilter) {
                    ForEach(DateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Spacer()

                // Sort order
                Picker("", selection: $store.sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            // Action items filter toggle
            Toggle(isOn: $store.hasActionItemsOnly) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text("Has action items")
                }
                .font(.caption)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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

    private var displaySnippet: String {
        entry.metadata.summarySnippet.isEmpty ? entry.snippet : entry.metadata.summarySnippet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Date + duration row
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, style: .date)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(entry.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Time + participant names row
            HStack(alignment: .center, spacing: 4) {
                Text(entry.date, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !entry.metadata.participantNames.isEmpty {
                    Text("·")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(entry.metadata.participantNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Action items badge
                if entry.metadata.actionItemCount > 0 {
                    ActionItemsBadge(count: entry.metadata.actionItemCount)
                }
            }

            // Snippet / summary
            if !displaySnippet.isEmpty {
                Text(displaySnippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - ActionItemsBadge

private struct ActionItemsBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "checklist")
                .font(.caption2)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.15))
        .foregroundColor(.accentColor)
        .cornerRadius(4)
    }
}
