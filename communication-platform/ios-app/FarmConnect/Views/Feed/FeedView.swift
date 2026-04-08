import SwiftUI

struct FeedView: View {
    struct ChatTarget: Identifiable, Hashable {
        let id: String
        let name: String
    }

    @EnvironmentObject private var viewModel: FeedViewModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var isCreatePostOpen = false
    @State private var selectedPost: Post?
    @State private var selectedChatTarget: ChatTarget?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search posts", text: $viewModel.query)
                        .textFieldStyle(.roundedBorder)

                    Button("Go") {
                        Task { await viewModel.load() }
                    }
                }
                .padding(.horizontal)

                HStack {
                    Picker("Category", selection: $viewModel.selectedCategory) {
                        Text("All types").tag("all")
                        Text("Disease").tag("Disease")
                        Text("Pest").tag("Pest")
                        Text("Weather").tag("Weather")
                        Text("Note").tag("Note")
                        Text("Market").tag("Market")
                    }
                    .pickerStyle(.menu)

                    Picker("Time", selection: $viewModel.selectedTimeFilter) {
                        ForEach(TimeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isLoading {
                    ProgressView("Loading posts...")
                        .frame(maxHeight: .infinity)
                } else {
                    List(viewModel.posts) { post in
                        HStack(alignment: .top, spacing: 10) {
                            let avatarText = String(post.userName.prefix(1)).uppercased()

                            if post.userId != session.currentUser?.id {
                                Button {
                                    selectedChatTarget = ChatTarget(id: post.userId, name: post.userName)
                                } label: {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Text(avatarText)
                                                .font(.caption.bold())
                                                .foregroundStyle(.blue)
                                        )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Text(avatarText)
                                            .font(.caption.bold())
                                            .foregroundStyle(.blue)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(post.userName)
                                            .font(.caption.bold())
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(relativeTime(post.createdAt))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(post.title)
                                        .font(.headline)

                                    let mediaUrls = resolvedMediaURLs(for: post)
                                    if mediaUrls.count == 1, let url = mediaUrls.first {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFit()
                                        } placeholder: {
                                            Color.gray.opacity(0.2)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: 320)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    } else if mediaUrls.count > 1 {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(mediaUrls, id: \.absoluteString) { url in
                                                    AsyncImage(url: url) { image in
                                                        image
                                                            .resizable()
                                                            .scaledToFill()
                                                    } placeholder: {
                                                        Color.gray.opacity(0.2)
                                                    }
                                                    .frame(width: 220, height: 160)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                                }
                                            }
                                        }
                                    }

                                    Text(post.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPost = post
                                }

                                HStack {
                                    Text(post.category.rawValue)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(categoryTagBackgroundColor(post.category), in: Capsule())
                                        .foregroundStyle(categoryTagTextColor(post.category))
                                    Text(post.city)
                                    Spacer()
                                    Button {
                                        Task { await viewModel.upvote(postId: post.id) }
                                    } label: {
                                        Label("\(post.upvotes)", systemImage: "arrow.up")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(categoryBackgroundColor(post.category))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(categoryBorderColor(post.category), lineWidth: 1)
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.load()
                    }
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let user = session.currentUser {
                            Text(user.name)
                        }
                        Button("Sign out", role: .destructive) {
                            session.logout()
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatePostOpen = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: viewModel.selectedCategory) { _, _ in
                Task { await viewModel.load() }
            }
            .onChange(of: viewModel.selectedTimeFilter) { _, _ in
                Task { await viewModel.load() }
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $isCreatePostOpen) {
                NewPostView()
                    .environmentObject(viewModel)
            }
            .navigationDestination(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .navigationDestination(item: $selectedChatTarget) { target in
                ChatThreadView(conversationId: nil, otherUserId: target.id, title: target.name)
                    .environmentObject(chatViewModel)
            }
        }
    }

    private func relativeTime(_ timestampMs: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func categoryBackgroundColor(_ category: Category) -> Color {
        switch category {
        case .note:
            return .gray.opacity(0.12)
        case .market:
            return .green.opacity(0.14)
        case .disease:
            return .red.opacity(0.12)
        case .pest:
            return .yellow.opacity(0.18)
        case .weather:
            return .blue.opacity(0.12)
        }
    }

    private func categoryBorderColor(_ category: Category) -> Color {
        switch category {
        case .note:
            return .gray.opacity(0.35)
        case .market:
            return .green.opacity(0.35)
        case .disease:
            return .red.opacity(0.35)
        case .pest:
            return .yellow.opacity(0.45)
        case .weather:
            return .blue.opacity(0.35)
        }
    }

    private func categoryTagBackgroundColor(_ category: Category) -> Color {
        switch category {
        case .note:
            return .gray.opacity(0.22)
        case .market:
            return .green.opacity(0.22)
        case .disease:
            return .red.opacity(0.22)
        case .pest:
            return .yellow.opacity(0.3)
        case .weather:
            return .blue.opacity(0.22)
        }
    }

    private func categoryTagTextColor(_ category: Category) -> Color {
        switch category {
        case .note:
            return .gray
        case .market:
            return .green
        case .disease:
            return .red
        case .pest:
            return .orange
        case .weather:
            return .blue
        }
    }

    private func resolvedMediaURLs(for post: Post) -> [URL] {
        post.imageUrls.compactMap { APIClient.shared.resolveMediaURL(from: $0) }
    }
}
