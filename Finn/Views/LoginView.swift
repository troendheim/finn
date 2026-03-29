import SwiftUI
import JellyfinAPI

struct LoginView: View {
    @Bindable var viewModel: LoginViewModel
    let imageService: ImageService?

    var body: some View {
        VStack(spacing: 40) {
            Text("Who's watching?")
                .font(.system(size: 48, weight: .bold))
                .padding(.top, 60)

            if viewModel.isLoading && viewModel.users.isEmpty {
                ProgressView()
            } else if viewModel.isShowingPassword {
                passwordView
            } else {
                userGrid
            }

            if let error = viewModel.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
        .task {
            await viewModel.loadUsers()
        }
    }

    private var userGrid: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 40) {
                ForEach(viewModel.users) { user in
                    Button {
                        viewModel.selectUser(user)
                    } label: {
                        VStack(spacing: 16) {
                            userAvatar(user)
                                .frame(width: 150, height: 150)
                                .clipShape(Circle())

                            Text(user.name ?? "Unknown")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 60)
        }
    }

    @ViewBuilder
    private func userAvatar(_ user: UserDto) -> some View {
        if let id = user.id, let url = imageService?.posterURL(itemID: id, maxWidth: 150) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                userInitial(user)
            }
        } else {
            userInitial(user)
        }
    }

    private func userInitial(_ user: UserDto) -> some View {
        ZStack {
            Circle().fill(.gray.opacity(0.3))
            Text(String((user.name ?? "?").prefix(1)).uppercased())
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var passwordView: some View {
        VStack(spacing: 30) {
            if let user = viewModel.selectedUser {
                Text(user.name ?? "")
                    .font(.title2)
            }

            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.plain)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 400)
                .onSubmit {
                    Task { await viewModel.signIn() }
                }

            HStack(spacing: 30) {
                Button("Cancel") {
                    viewModel.cancelPassword()
                }

                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(width: 120)
                    } else {
                        Text("Sign In")
                            .frame(width: 120)
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}
