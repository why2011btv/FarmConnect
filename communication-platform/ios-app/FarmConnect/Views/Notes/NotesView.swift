import SwiftUI

struct NotesView: View {
    enum NotesSource: String, CaseIterable, Identifiable {
        case fieldLog = "Field log"
        case privateNotes = "Private notes"
        var id: String { rawValue }
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case list = "List"
        case calendar = "Calendar"
        var id: String { rawValue }
    }

    enum FieldLogFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case spray = "Spray"
        case scouting = "Scouting"
        var id: String { rawValue }

        var kind: VineyardLogKind? {
            switch self {
            case .all: return nil
            case .spray: return .spray
            case .scouting: return .scouting
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
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var notesSource: NotesSource = .fieldLog
    @State private var fieldLogFilter: FieldLogFilter = .all
    @State private var isCreateNoteOpen = false
    @State private var isCreateFieldLogOpen = false
    @State private var displayMode: DisplayMode = .list
    @State private var displayedMonth = NotesView.startOfMonth(Date())
    @State private var selectedCalendarDay = Calendar.current.startOfDay(for: Date())
    @State private var pendingDeletion: Post?
    @State private var isDeleting = false

    private var filteredFieldEntries: [VineyardFieldLogEntry] {
        let base = fieldLogStore.entries(kind: fieldLogFilter.kind)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Source", selection: $notesSource) {
                    ForEach(NotesSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack {
                    TextField(notesSource == .fieldLog ? "Search field log" : "Search private notes", text: $query)
                        .textFieldStyle(.roundedBorder)
                    if notesSource == .privateNotes {
                        Button("Go") {
                            Task { await loadNotes() }
                        }
                    }
                }
                .padding(.horizontal)

                if notesSource == .fieldLog {
                    Picker("Type", selection: $fieldLogFilter) {
                        ForEach(FieldLogFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                } else {
                    Picker("Time", selection: $selectedTimeFilter) {
                        ForEach(TimeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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
                    if notesSource == .fieldLog {
                        fieldLogContent
                    } else {
                        privateNotesContent
                    }

                    if isLoading && notes.isEmpty && notesSource == .privateNotes {
                        ProgressView("Loading private notes...")
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if notesSource == .fieldLog {
                            isCreateFieldLogOpen = true
                        } else {
                            isCreateNoteOpen = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(notesSource == .fieldLog ? "Add field log entry" : "Create Note")
                }
            }
            .task {
                fieldLogStore.reload()
                await loadNotes()
            }
            .onChange(of: feedViewModel.refreshTrigger) { _, _ in
                Task { await loadNotes() }
            }
            .onChange(of: selectedTimeFilter) { _, _ in
                Task { await loadNotes() }
            }
            .onChange(of: selectedCalendarDay) { _, newValue in
                displayedMonth = Self.startOfMonth(newValue)
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

    // MARK: - Field log

    @ViewBuilder
    private var fieldLogContent: some View {
        if displayMode == .list {
            fieldLogList
                .overlay {
                    if filteredFieldEntries.isEmpty {
                        ContentUnavailableView(
                            "No field log entries",
                            systemImage: "leaf.arrow.triangle.circlepath",
                            description: Text("Demo spray and scouting records appear here. Tap + to add your own.")
                        )
                    }
                }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    fieldLogSummaryBanner
                    calendarView(entriesByDay: fieldEntriesByDay)
                    selectedDayFieldLogSection
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var fieldLogSummaryBanner: some View {
        let sprays = fieldLogStore.entries.filter { $0.kind == .spray }.count
        let scouts = fieldLogStore.entries.filter { $0.kind == .scouting }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text("Vineyard field log")
                .font(.subheadline.weight(.semibold))
            Text("\(sprays) spray records · \(scouts) scouting notes · block + row detail")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var fieldLogList: some View {
        List {
            if fieldLogFilter == .all {
                fieldLogSection(
                    title: "Spray applications",
                    entries: filteredFieldEntries.filter { $0.kind == .spray }
                )
                fieldLogSection(
                    title: "Scouting & issues",
                    entries: filteredFieldEntries.filter { $0.kind == .scouting }
                )
            } else {
                fieldLogRows(filteredFieldEntries)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func fieldLogSection(title: String, entries: [VineyardFieldLogEntry]) -> some View {
        if !entries.isEmpty {
            Section(title) {
                fieldLogRows(entries)
            }
        }
    }

    private func fieldLogRows(_ items: [VineyardFieldLogEntry]) -> some View {
        ForEach(items) { entry in
            VineyardFieldLogCard(entry: entry)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
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
        }
    }

    private var fieldEntriesByDay: [Date: [VineyardFieldLogEntry]] {
        Dictionary(grouping: filteredFieldEntries) { entry in
            Calendar.current.startOfDay(for: entry.createdAt)
        }
    }

    private var selectedDayFieldEntries: [VineyardFieldLogEntry] {
        (fieldEntriesByDay[selectedCalendarDay] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedDayFieldLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entries on \(dayTitle(for: selectedCalendarDay))")
                .font(.headline)
                .padding(.horizontal)

            if selectedDayFieldEntries.isEmpty {
                Text("No entries on this date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(selectedDayFieldEntries) { entry in
                    VineyardFieldLogCard(entry: entry)
                        .padding(.horizontal)
                        .onTapGesture {
                            selectedFieldEntry = entry
                        }
                }
            }
        }
    }

    // MARK: - Private notes (API)

    @ViewBuilder
    private var privateNotesContent: some View {
        if displayMode == .list {
            notesList(notes)
                .overlay {
                    if notes.isEmpty && !isLoading {
                        ContentUnavailableView(
                            "No private notes",
                            systemImage: "note.text",
                            description: Text("Use Field log for structured spray and scouting records.")
                        )
                    }
                }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    calendarView(entriesByDay: nil)
                    if notes.isEmpty && !isLoading {
                        ContentUnavailableView("No private notes", systemImage: "note.text")
                            .padding(.top, 24)
                    } else {
                        selectedDayNotesSection
                    }
                }
                .padding(.bottom, 12)
            }
            .refreshable {
                await loadNotes()
            }
        }
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
                query: query,
                timeFilter: selectedTimeFilter,
                limit: 100
            )
            notes = page.items
        } catch {
            if isCancellationError(error) { return }
            errorMessage = "Failed to load private notes: \(error.localizedDescription)"
        }
    }

    private var notesByDay: [Date: [Post]] {
        Dictionary(grouping: notes) { note in
            let date = Date(timeIntervalSince1970: Double(note.createdAt) / 1000)
            return Calendar.current.startOfDay(for: date)
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

    private var selectedDayNotes: [Post] {
        (notesByDay[selectedCalendarDay] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let sources: [Date] = notesSource == .fieldLog
            ? filteredFieldEntries.map(\.createdAt)
            : notes.map { Date(timeIntervalSince1970: Double($0.createdAt) / 1000) }
        let noteYears = sources.map { calendar.component(.year, from: $0) }
        let minimum = min(noteYears.min() ?? currentYear, currentYear - 3)
        let maximum = max(noteYears.max() ?? currentYear, currentYear + 3)
        return Array(minimum...maximum)
    }

    private func calendarView(entriesByDay: [Date: [VineyardFieldLogEntry]]?) -> some View {
        let hasEntry: (Date) -> Bool = { date in
            if let entriesByDay {
                return entriesByDay[date] != nil
            }
            return notesByDay[date] != nil
        }
        let dotColor: Color = notesSource == .fieldLog ? .green : .blue

        return VStack(alignment: .leading, spacing: 10) {
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
                        dayCell(for: date, hasNotes: hasEntry(date), accent: dotColor)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
            .padding(.horizontal)
        }
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

    private func dayCell(for date: Date, hasNotes: Bool, accent: Color) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedCalendarDay)
        return Button {
            selectedCalendarDay = date
        } label: {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(hasNotes ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hasNotes ? accent : Color.gray.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.primary.opacity(0.8) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var selectedDayNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes on \(dayTitle(for: selectedCalendarDay))")
                .font(.headline)
                .padding(.horizontal)

            if selectedDayNotes.isEmpty {
                Text("No notes on this date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(selectedDayNotes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(note.title)
                                .font(.headline)
                            Spacer()
                            Button {
                                pendingDeletion = note
                            } label: {
                                Image(systemName: "trash")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
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
                    .padding(10)
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPost = note
                    }
                }
            }
        }
    }

    private func notesList(_ notes: [Post]) -> some View {
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDeletion = note
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadNotes()
        }
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
