import SwiftUI

struct NotesView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case list = "List"
        case calendar = "Calendar"
        var id: String { rawValue }
    }

    @EnvironmentObject private var feedViewModel: FeedViewModel
    @State private var notes: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPost: Post?
    @State private var query = ""
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var isCreateNoteOpen = false
    @State private var displayMode: DisplayMode = .list
    @State private var displayedMonth = NotesView.startOfMonth(Date())
    @State private var selectedCalendarDay = Calendar.current.startOfDay(for: Date())

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

                if isLoading {
                    ProgressView("Loading private notes...")
                        .frame(maxHeight: .infinity)
                } else if notes.isEmpty {
                    ContentUnavailableView("No private notes", systemImage: "note.text")
                        .frame(maxHeight: .infinity)
                } else if displayMode == .list {
                    notesList(notes)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            calendarView
                            selectedDayNotesSection
                        }
                        .padding(.bottom, 12)
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
            if isCancellation(error) {
                return
            }
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
        let noteYears = notes.map { note in
            calendar.component(.year, from: Date(timeIntervalSince1970: Double(note.createdAt) / 1000))
        }
        let minimum = min(noteYears.min() ?? currentYear, currentYear - 3)
        let maximum = max(noteYears.max() ?? currentYear, currentYear + 3)
        return Array(minimum...maximum)
    }

    private var calendarView: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdaySymbols(), id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: 34)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func dayCell(for date: Date) -> some View {
        let hasNotes = notesByDay[date] != nil
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
                        .fill(hasNotes ? Color.blue : Color.gray.opacity(0.2))
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(selectedDayNotes) { note in
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
                    .padding(10)
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
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
        guard month >= 1, month <= symbols.count else {
            return "\(month)"
        }
        return symbols[month - 1]
    }

    private func updateDisplayedMonth(month: Int?, year: Int?) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: displayedMonth)
        if let month {
            components.month = month
        }
        if let year {
            components.year = year
        }
        guard let newMonth = calendar.date(from: components).map({ Self.startOfMonth($0) }) else {
            return
        }
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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }
}
