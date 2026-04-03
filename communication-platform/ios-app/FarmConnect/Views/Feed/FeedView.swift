import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var viewModel: FeedViewModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var chatViewModel: ChatViewModel

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

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isLoading {
                    ProgressView("Loading posts...")
                        .frame(maxHeight: .infinity)
                } else {
                    List(viewModel.posts) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                NavigationLink {
                                    PostDetailView(post: post)
                                } label: {
                                    Text(post.title)
                                        .font(.headline)
                                }
                                Spacer()
                                if post.userId != session.currentUser?.id {
                                    NavigationLink {
                                        ChatThreadView(conversationId: nil, otherUserId: post.userId, title: post.userName)
                                            .environmentObject(chatViewModel)
                                    } label: {
                                        Text(post.userName)
                                            .font(.caption)
                                    }
                                } else {
                                    Text(post.userName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let imageUrl = post.imageUrl, let url = APIClient.shared.resolveMediaURL(from: imageUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(post.category.rawValue)
                                Text(post.city)
                                Spacer()
                                Button("Upvote (\(post.upvotes))") {
                                    Task { await viewModel.upvote(postId: post.id) }
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.load()
                    }
                }
            }
            .padding()
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
        }
    }
}
