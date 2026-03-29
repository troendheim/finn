import Foundation
import JellyfinAPI

@MainActor
@Observable
final class LoginViewModel {
    var users: [UserDto] = []
    var selectedUser: UserDto?
    var password = ""
    var isLoading = false
    var isShowingPassword = false
    var error: String?
    var isLoggedIn = false

    private let jellyfinService: JellyfinService

    init(jellyfinService: JellyfinService) {
        self.jellyfinService = jellyfinService
    }

    func loadUsers() async {
        isLoading = true
        error = nil
        do {
            users = try await jellyfinService.getPublicUsers()
        } catch {
            self.error = "Failed to load users"
        }
        isLoading = false
    }

    func selectUser(_ user: UserDto) {
        selectedUser = user
        password = ""
        error = nil
        if user.hasPassword == true {
            isShowingPassword = true
        } else {
            Task { await signIn() }
        }
    }

    func signIn() async {
        guard let user = selectedUser, let username = user.name else {
            error = "No user selected"
            return
        }

        isLoading = true
        error = nil

        do {
            try await jellyfinService.signIn(username: username, password: password)
            isLoggedIn = true
        } catch {
            self.error = "Login failed. Check your password."
        }

        isLoading = false
    }

    func cancelPassword() {
        isShowingPassword = false
        selectedUser = nil
        password = ""
        error = nil
    }
}
