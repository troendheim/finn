import Foundation
import JellyfinAPI

@MainActor
@Observable
final class ServerConnectViewModel {
    var serverURLText = ""
    var isConnecting = false
    var error: String?
    var isConnected = false
    var isInsecureWarning = false

    private let jellyfinService: JellyfinService

    init(jellyfinService: JellyfinService) {
        self.jellyfinService = jellyfinService
    }

    func connect() async {
        let trimmed = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Please enter a server URL"
            return
        }

        // Add https:// if no scheme
        var urlString = trimmed
        if !urlString.contains("://") {
            urlString = "https://\(urlString)"
        }

        // Strip trailing slashes
        while urlString.hasSuffix("/") {
            urlString.removeLast()
        }

        guard let url = URL(string: urlString), url.host != nil else {
            error = "Invalid URL"
            return
        }

        // Warn about insecure connections (but allow them)
        if url.scheme == "http" {
            isInsecureWarning = true
        }

        isConnecting = true
        error = nil

        do {
            try await jellyfinService.connectToServer(url: url)
            isConnected = true
        } catch {
            self.error = "Could not connect to server: \(error.localizedDescription)"
        }

        isConnecting = false
    }
}
