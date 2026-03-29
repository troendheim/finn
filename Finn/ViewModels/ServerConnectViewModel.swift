import Foundation
import JellyfinAPI

@MainActor
@Observable
final class ServerConnectViewModel {
    var serverURLText = ""
    var isConnecting = false
    var error: String?
    var isConnected = false

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

        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            return
        }

        isConnecting = true
        error = nil

        do {
            try await jellyfinService.connectToServer(url: url)
            isConnected = true
        } catch {
            self.error = "Could not connect to server. Check the URL and try again."
        }

        isConnecting = false
    }
}
