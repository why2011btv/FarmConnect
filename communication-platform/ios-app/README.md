# iOS App (SwiftUI Skeleton)

This folder contains a SwiftUI-first scaffold for the communication platform MVP.

## Current scope

- Feed tab (posts list + filters)
- Map tab placeholder (to connect MapKit)
- New Post form with photo upload to backend
- Chat tab with conversation list + thread send/load
- Login + session restore + sign-out
- APNs registration scaffold and backend device-token registration
- Shared API client for backend endpoints

## Generate an Xcode project

This scaffold includes `project.yml` for [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd communication-platform/ios-app
brew install xcodegen
xcodegen generate
open FarmConnect.xcodeproj
```

## Configure backend URL

In `FarmConnect/Networking/APIClient.swift`, update `baseURL` to your cloud API endpoint.

## Next steps

1. Add login/auth screens and token storage.
2. Build post details, comments sheet, and create post form.
3. Integrate APNs token registration route.
4. Add map pins with MapKit and open post flow.
