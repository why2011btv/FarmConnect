import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @State private var notes: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPost: Post?
    @State private var query = ""
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var isCreateNoteOpen = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search private notes", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button("Go") {
                        Task { await loadNotes() }
                    }
                }
                .padding(.horizontal)

                Picker("Time", selection: $selectedTimeFilter) {
                    ForEach(TimeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLoading {
                    ProgressView("Loading private notes...")
                        .frame(maxHeight: .infinity)
                } else if notes.isEmpty {
                    ContentUnavailableView("No private notes", systemImage: "note.text")
                        .frame(maxHeight: .infinity)
                } else {
                    List(notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.title)
                                .font(.headline)
                            Text(note.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            HStack {
                                Text(note.city)
                                Spacer()
                                Text(relativeTime(note.createdAt))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPost = note
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadNotes()
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreateNoteOpen = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Note")
                }
            }
            .task {
                await loadNotes()
            }
            .onChange(of: feedViewModel.refreshTrigger) { _, _ in
                Task { await loadNotes() }
            }
            .onChange(of: selectedTimeFilter) { _, _ in
                Task { await loadNotes() }
            }
            .sheet(isPresented: $isCreateNoteOpen) {
                NewPostView(
                    initialCategory: .note,
                    initialVisibility: "Private",
                    screenTitle: "Create Note",
                    publishButtonTitle: "Save Note",
                    successMessage: "Note saved"
                )
                .environmentObject(feedViewModel)
            }
            .navigationDestination(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
        }
    }

    private func loadNotes() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            notes = try await APIClient.shared.getPrivateNotes(
                query: query,
                timeFilter: selectedTimeFilter
            )
        } catch {
            notes = []
            errorMessage = "Failed to load private notes: \(error.localizedDescription)"
        }
    }

    private func relativeTime(_ timestampMs: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
