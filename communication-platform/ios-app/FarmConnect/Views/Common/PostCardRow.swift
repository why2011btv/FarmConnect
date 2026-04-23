import SwiftUI

/// Reusable card row used in the Feed list.
///
/// Rendering is purely presentational; callers supply closures for all
/// side-effects (tap post, tap user avatar, tap media, upvote).
struct PostCardRow: View {
    let post: Post
    let currentUserId: String?
    let onTapPost: () -> Void
    let onTapAuthor: () -> Void
    let onUpvote: () -> Void
    let onTapMedia: (_ mediaURLs: [URL], _ startIndex: Int) -> Void

    private var mediaURLs: [URL] {
        post.imageUrls.compactMap { APIClient.shared.resolveMediaURL(from: $0) }
    }

    private var isOwnPost: Bool {
        post.userId == currentUserId
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 8) {
                content
                footer
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(post.category.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(post.category.cardBorder, lineWidth: 1)
        )
    }

    private var avatar: some View {
        let avatarText = String(post.userName.prefix(1)).uppercased()
        return Group {
            if isOwnPost {
                avatarCircle(avatarText)
            } else {
                Button(action: onTapAuthor) {
                    avatarCircle(avatarText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func avatarCircle(_ text: String) -> some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .frame(width: 34, height: 34)
            .overlay(
                Text(text)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(post.userName)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text(TimeFormatting.relative(from: post.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(post.title)
                .font(.headline)

            mediaSection

            Text(post.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapPost)
    }

    @ViewBuilder
    private var mediaSection: some View {
        let urls = mediaURLs
        if urls.count == 1, let url = urls.first {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 320)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { onTapMedia([url], 0) }
        } else if urls.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(urls.enumerated()), id: \.element.absoluteString) { index, url in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 220, height: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture { onTapMedia(urls, index) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(post.category.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(post.category.tagBackground, in: Capsule())
                .foregroundStyle(post.category.tagForeground)
            Text(post.city)
            Spacer()
            Button(action: onUpvote) {
                Label("\(post.upvotes)", systemImage: "arrow.up")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
    }
}
