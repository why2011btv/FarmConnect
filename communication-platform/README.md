# Communication Platform (Native-First)

This directory contains the first build of the communication platform:

- `backend/`: TypeScript API for posts, comments, upvotes, conversations, messages, and upload URL stubs.
- `ios-app/`: SwiftUI app skeleton for TestFlight-targeted development.

## MVP features included

- Posts + comments + upvotes
- Feed filters (search, category, time)
- 1:1 direct messages
- Image upload flow (signed-upload URL placeholder)
- Push notifications scaffold point (backend endpoint + iOS app service hook)

## What is in-progress

- Authentication and authorization are scaffolded but not production-ready.
- Persistence is in-memory for now (next step: Postgres + managed auth).
- iOS project is a code skeleton and needs to be opened in Xcode with a generated project.

## Next steps

1. Run backend locally and validate API responses.
2. Generate/open iOS project and connect base URL.
3. Replace in-memory store with Postgres repository layer.
4. Add APNs push pipeline for DM/comment notifications.
