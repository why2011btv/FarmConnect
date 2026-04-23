import Foundation

/// Returns true for `Task` cancellation and `URLSession` cancellation errors.
/// Used to suppress spurious "Failed to load..." banners when SwiftUI cancels
/// in-flight `.task` / `.refreshable` work during view updates.
func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}
