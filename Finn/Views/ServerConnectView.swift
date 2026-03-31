import SwiftUI

struct ServerConnectView: View {
    @Bindable var viewModel: ServerConnectViewModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("Finn")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Connect to your Jellyfin server")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 20) {
                TextField("Server URL (e.g. https://jellyfin.example.com)", text: $viewModel.serverURLText)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 600)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await viewModel.connect() }
                    }

                Button {
                    Task { await viewModel.connect() }
                } label: {
                    if viewModel.isConnecting {
                        ProgressView()
                            .frame(width: 200)
                    } else {
                        Text("Connect")
                            .frame(width: 200)
                    }
                }
                .disabled(viewModel.isConnecting)

                if viewModel.isInsecureWarning {
                    Label("Insecure connection (HTTP). Your data will not be encrypted.", systemImage: "lock.open")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if let error = viewModel.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Spacer()
            Spacer()
        }
        .padding()
    }
}
