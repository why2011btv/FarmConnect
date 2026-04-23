import SwiftUI

struct FeedView: View {
    struct ChatTarget: Identifiable, Hashable {
        let id: String
        let name: String
    }

    struct FullscreenMediaPayload: Identifiable {
        let id = UUID()
        let mediaURLs: [URL]
        let startIndex: Int
    }

    @EnvironmentObject private var viewModel: FeedViewModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var isCreatePostOpen = false
    @State private var selectedPost: Post?
    @State private var selectedChatTarget: ChatTarget?
    @State private var fullscreenMedia: FullscreenMediaPayload?
    @State private var pendingDeletion: Post?

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

                ZStack {
                    List {
                        ForEach(viewModel.posts) { post in
                            PostCardRow(
                                post: post,
                                currentUserId: session.currentUser?.id,
                                onTapPost: { selectedPost = post },
                                onTapAuthor: {
                                    selectedChatTarget = ChatTarget(id: post.userId, name: post.userName)
                                },
                                onUpvote: {
                                    Task { await viewModel.upvote(postId: post.id) }
                                },
                                onTapMedia: { urls, index in
                                    openFullscreen(mediaUrls: urls, startIndex: index)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if post.userId == session.currentUser?.id {
                                    Button(role: .destructive) {
                                        pendingDeletion = post
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .onAppear {
                                // Trigger the next page load as soon as we get
                                // within a few rows of the bottom.
                                if shouldTriggerLoadMore(for: post) {
                                    Task { await viewModel.loadMoreIfNeeded() }
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.load()
                    }

                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        ProgressView("Loading posts...")
                    } else if viewModel.posts.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView {
                            Label("No posts yet", systemImage: "leaf")
                        } description: {
                            Text("Pull to refresh, or tap + to share what's happening on your farm.")
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenuButton()
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
            .fullScreenCover(item: $fullscreenMedia) { payload in
                FullscreenMediaViewer(
                    mediaURLs: payload.mediaURLs,
                    initialIndex: payload.startIndex
                ) {
                    fullscreenMedia = nil
                }
            }
            .alert(
                "Delete this post?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { post in
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deletePost(postId: post.id)
                        pendingDeletion = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { post in
                Text("“\(post.title)” will be permanently removed, along with its comments and likes.")
            }
        }
    }

    private func openFullscreen(mediaUrls: [URL], startIndex: Int) {
        guard !mediaUrls.isEmpty else { return }
        let clampedIndex = min(max(0, startIndex), mediaUrls.count - 1)
        fullscreenMedia = FullscreenMediaPayload(mediaURLs: mediaUrls, startIndex: clampedIndex)
    }

    /// Returns true if `post` is within the last 5 items of the current list,
    /// so we can pre-fetch the next page before the user hits the bottom.
    private func shouldTriggerLoadMore(for post: Post) -> Bool {
        guard let index = viewModel.posts.firstIndex(where: { $0.id == post.id }) else { return false }
        return index >= viewModel.posts.count - 5
    }
}

struct FullscreenMediaViewer: View {
    let mediaURLs: [URL]
    let initialIndex: Int
    let onClose: () -> Void
    @State private var selectedIndex: Int

    init(mediaURLs: [URL], initialIndex: Int, onClose: @escaping () -> Void) {
        self.mediaURLs = mediaURLs
        self.initialIndex = initialIndex
        self.onClose = onClose
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(mediaURLs.enumerated()), id: \.element.absoluteString) { index, url in
                    ZoomableRemoteImage(url: url)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding()
        }
    }
}

private struct ZoomableRemoteImage: View {
    let url: URL
    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .scaleEffect(zoomScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let proposed = committedZoomScale * value
                            zoomScale = min(max(proposed, 1), 4)
                        }
                        .onEnded { _ in
                            committedZoomScale = zoomScale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if zoomScale > 1.1 {
                            zoomScale = 1
                            committedZoomScale = 1
                        } else {
                            zoomScale = 2.5
                            committedZoomScale = 2.5
                        }
                    }
                }
        } placeholder: {
            ProgressView()
                .tint(.white)
        }
    }
}
