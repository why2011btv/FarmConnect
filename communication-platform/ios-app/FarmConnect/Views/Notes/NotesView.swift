import SwiftUI

struct NotesView: View {
    enum NotesFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case spray = "Spray"
        case scouting = "Scouting"
        case notes = "Notes"
        var id: String { rawValue }

        var fieldLogKind: VineyardLogKind? {
            switch self {
            case .all, .notes: return nil
            case .spray: return .spray
            case .scouting: return .scouting
            }
        }
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case list = "List"
        case calendar = "Calendar"
        var id: String { rawValue }
    }

    private enum TimelineItem: Identifiable {
        case field(VineyardFieldLogEntry)
        case note(Post)

        var id: String {
            switch self {
            case .field(let entry): return "field-\(entry.id)"
            case .note(let post): return "note-\(post.id)"
            }
        }

        var sortDate: Date {
            switch self {
            case .field(let entry): return entry.createdAt
            case .note(let post):
                return Date(timeIntervalSince1970: Double(post.createdAt) / 1000)
            }
        }
    }

    @EnvironmentObject private var feedViewModel: FeedViewModel
    @ObservedObject private var fieldLogStore = VineyardFieldLogStore.shared

    @State private var notes: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPost: Post?
    @State private var selectedFieldEntry: VineyardFieldLogEntry?
    @State private var query = ""
    @State private var notesFilter: NotesFilter = .all
    @State private var isCreateNoteOpen = false
    @State private var isCreateFieldLogOpen = false
    @State private var displayMode: DisplayMode = .list
    @State private var displayedMonth = NotesView.startOfMonth(Date())
    @State private var selectedCalendarDay = Calendar.current.startOfDay(for: Date())
    @State private var pendingDeletion: Post?
    @State private var isDeleting = false

    private var filteredFieldEntries: [VineyardFieldLogEntry] {
        let base = fieldLogStore.entries(kind: notesFilter.fieldLogKind)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.notes.localizedCaseInsensitiveContains(trimmed)
                || $0.locationDetail.localizedCaseInsensitiveContains(trimmed)
                || ($0.blockName?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || $0.grapeVariety.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var filteredPrivateNotes: [Post] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.body.localizedCaseInsensitiveContains(trimmed)
                || $0.city.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var timelineItems: [TimelineItem] {
        switch notesFilter {
        case .all:
            let fields = filteredFieldEntries.map { TimelineItem.field($0) }
            let noteItems = filteredPrivateNotes.map { TimelineItem.note($0) }
            return (fields + noteItems).sorted { $0.sortDate > $1.sortDate }
        case .spray, .scouting:
            return filteredFieldEntries
                .map { TimelineItem.field($0) }
                .sorted { $0.sortDate > $1.sortDate }
        case .notes:
            return filteredPrivateNotes
                .map { TimelineItem.note($0) }
                .sorted { $0.sortDate > $1.sortDate }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Search notes and field log", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Picker("Filter", selection: $notesFilter) {
                    ForEach(NotesFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Picker("Mode", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ZStack {
                    if displayMode == .list {
                        unifiedList
                            .overlay {
                                if timelineItems.isEmpty && !isLoading {
                                    ContentUnavailableView(
                                        emptyTitle,
                                        systemImage: "note.text",
                                        description: Text(emptyDescription)
                                    )
                                }
                            }
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                calendarView
                                selectedDaySection
                            }
                            .padding(.bottom, 12)
                        }
                        .refreshable {
                            await reloadAll()
                        }
                    }

                    if isLoading && notes.isEmpty {
                        ProgressView("Loading notes...")
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isCreateFieldLogOpen = true
                        } label: {
                            Label("Field log entry", systemImage: "leaf.arrow.triangle.circlepath")
                        }
                        Button {
                            isCreateNoteOpen = true
                        } label: {
                            Label("Quick note", systemImage: "note.text")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add note")
                }
            }
            .task {
                await reloadAll()
            }
            .onChange(of: feedViewModel.refreshTrigger) { _, _ in
                Task { await loadNotes() }
            }
            .onChange(of: selectedCalendarDay) { _, newValue in
                displayedMonth = Self.startOfMonth(newValue)
            }
            .sheet(isPresented: $isCreateNoteOpen) {
                NewPostView(
                    initialCategory: .note,
                    initialVisibility: "Private",
                    screenTitle: "Quick Note",
                    publishButtonTitle: "Save Note",
                    successMessage: "Note saved"
                )
                .environmentObject(feedViewModel)
            }
            .sheet(isPresented: $isCreateFieldLogOpen) {
                NewVineyardLogEntryView()
            }
            .navigationDestination(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .navigationDestination(item: $selectedFieldEntry) { entry in
                VineyardFieldLogDetailView(
                    entry: entry,
                    onDelete: entry.isBundledDemo
                        ? nil
                        : {
                            fieldLogStore.delete(entry)
                            selectedFieldEntry = nil
                        }
                )
            }
            .alert(
                "Delete this note?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { note in
                Button("Delete", role: .destructive) {
                    Task { await deleteNote(note) }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { note in
                Text("“\(note.title)” will be permanently removed.")
            }
        }
    }

    private var emptyTitle: String {
        switch notesFilter {
        case .all: return "No notes yet"
        case .spray: return "No spray records"
        case .scouting: return "No scouting notes"
        case .notes: return "No quick notes"
        }
    }

    private var emptyDescription: String {
        switch notesFilter {
        case .all:
            return "Add a field log entry for spray or scouting, or jot a quick private note."
        case .spray, .scouting:
            return "Tap + to add a structured field log entry."
        case .notes:
            return "Tap + to save a quick private note."
        }
    }

    // MARK: - Unified list

    private var unifiedList: some View {
        List {
            ForEach(timelineItems) { item in
                timelineRow(item)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await reloadAll()
        }
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineItem) -> some View {
        switch item {
        case .field(let entry):
            VineyardFieldLogCard(entry: entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedFieldEntry = entry
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !entry.isBundledDemo {
                        Button(role: .destructive) {
                            fieldLogStore.delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        case .note(let note):
            privateNoteRow(note)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = note
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    private func privateNoteRow(_ note: Post) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                Text("Quick note")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(relativeTime(note.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(note.title)
                .font(.headline)
            if !note.body.isEmpty {
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPost = note
        }
    }

    // MARK: - Calendar

    private var entriesByDay: [Date: [TimelineItem]] {
        Dictionary(grouping: timelineItems) { item in
            Calendar.current.startOfDay(for: item.sortDate)
        }
    }

    private var selectedDayItems: [TimelineItem] {
        (entriesByDay[selectedCalendarDay] ?? []).sorted { $0.sortDate > $1.sortDate }
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entries on \(dayTitle(for: selectedCalendarDay))")
                .font(.headline)
                .padding(.horizontal)

            if selectedDayItems.isEmpty {
                Text("Nothing on this date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(selectedDayItems) { item in
                    timelineRow(item)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var calendarView: some View {
        VStack(alignment: .leading, spacing: 10) {
            calendarHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdaySymbols(), id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date, hasEntries: entriesByDay[date] != nil)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Data

    private func reloadAll() async {
        fieldLogStore.reload()
        await loadNotes()
    }

    private func deleteNote(_ note: Post) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await APIClient.shared.deletePost(postId: note.id)
            notes.removeAll { $0.id == note.id }
            pendingDeletion = nil
            feedViewModel.refreshTrigger = UUID()
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            pendingDeletion = nil
        }
    }

    private func loadNotes() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await APIClient.shared.getPrivateNotes(
                query: "",
                timeFilter: .all,
                limit: 100
            )
            notes = page.items
        } catch {
            if isCancellationError(error) { return }
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
        }
    }

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let firstWeekdayOfMonth = calendar.component(.weekday, from: displayedMonth)
        let leadingBlanks = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7
        var items: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: displayedMonth) {
                items.append(calendar.startOfDay(for: date))
            }
        }
        return items
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let dates = timelineItems.map(\.sortDate)
        let years = dates.map { calendar.component(.year, from: $0) }
        let minimum = min(years.min() ?? currentYear, currentYear - 3)
        let maximum = max(years.max() ?? currentYear, currentYear + 3)
        return Array(minimum...maximum)
    }

    private var calendarHeader: some View {
        HStack {
            Button {
                if let previous = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) {
                    displayedMonth = Self.startOfMonth(previous)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            let month = Calendar.current.component(.month, from: displayedMonth)
            let year = Calendar.current.component(.year, from: displayedMonth)
            HStack(spacing: 8) {
                Menu {
                    Picker("Month", selection: Binding(
                        get: { month },
                        set: { updateDisplayedMonth(month: $0, year: nil) }
                    )) {
                        ForEach(1...12, id: \.self) { value in
                            Text(monthName(for: value)).tag(value)
                        }
                    }
                } label: {
                    Label(monthName(for: month), systemImage: "chevron.down")
                        .font(.headline)
                }

                Menu {
                    Picker("Year", selection: Binding(
                        get: { year },
                        set: { updateDisplayedMonth(month: nil, year: $0) }
                    )) {
                        ForEach(availableYears, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                } label: {
                    Label("\(year)", systemImage: "chevron.down")
                        .font(.headline)
                }
            }
            Spacer()
            Button {
                if let next = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) {
                    displayedMonth = Self.startOfMonth(next)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
    }

    private func dayCell(for date: Date, hasEntries: Bool) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedCalendarDay)
        return Button {
            selectedCalendarDay = date
        } label: {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(hasEntries ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hasEntries ? Color.accentColor : Color.gray.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.primary.opacity(0.8) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func weekdaySymbols() -> [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    private func monthName(for month: Int) -> String {
        let symbols = DateFormatter().monthSymbols ?? []
        guard month >= 1, month <= symbols.count else { return "\(month)" }
        return symbols[month - 1]
    }

    private func updateDisplayedMonth(month: Int?, year: Int?) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: displayedMonth)
        if let month { components.month = month }
        if let year { components.year = year }
        guard let newMonth = calendar.date(from: components).map({ Self.startOfMonth($0) }) else { return }
        displayedMonth = newMonth
        if !calendar.isDate(selectedCalendarDay, equalTo: newMonth, toGranularity: .month) {
            selectedCalendarDay = newMonth
        }
    }

    private func dayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
    }

    private func relativeTime(_ timestampMs: Int64) -> String {
        TimeFormatting.relative(from: timestampMs)
    }
}
