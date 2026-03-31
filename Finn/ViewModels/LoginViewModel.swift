import Foundation
import JellyfinAPI

@MainActor
@Observable
final class LoginViewModel {
    var users: [UserDto] = []
    var selectedUser: UserDto?
    var username = ""
    var password = ""
    var isLoading = false
    var isShowingPassword = false
    var isManualLogin = false
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
            // If no public users, fall back to manual login
            if users.isEmpty {
                isManualLogin = true
            }
        } catch {
            // If fetching users fails, fall back to manual login
            isManualLogin = true
        }
        isLoading = false
    }

    func selectUser(_ user: UserDto) {
        selectedUser = user
        username = user.name ?? ""
        password = ""
        error = nil
        if user.hasPassword == false {
            Task { await signIn() }
        } else {
            isShowingPassword = true
        }
    }

    func signIn() async {
        let loginUsername: String
        if let user = selectedUser, let name = user.name {
            loginUsername = name
        } else if !username.isEmpty {
            loginUsername = username
        } else {
            error = "Please enter a username"
            return
        }

        isLoading = true
        error = nil

        do {
            try await jellyfinService.signIn(username: loginUsername, password: password)
            isLoggedIn = true
        } catch {
            self.error = "Login failed. Check your credentials."
        }

        isLoading = false
    }

    func cancelPassword() {
        isShowingPassword = false
        selectedUser = nil
        username = ""
        password = ""
        error = nil
    }
}
