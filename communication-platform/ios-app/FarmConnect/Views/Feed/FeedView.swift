import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var viewModel: FeedViewModel

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
                        Text("All").tag("all")
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
                        NavigationLink {
                            PostDetailView(post: post)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(post.title)
                                    .font(.headline)
                                if let imageUrl = post.imageUrl, let url = URL(string: imageUrl) {
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
                    }
                    .listStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task { await viewModel.load() }
                    }
                }
            }
            .task {
                await viewModel.load()
            }
        }
    }
}
