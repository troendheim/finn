// Finn/Placeholders.swift
// Temporary stubs — will be replaced by real implementations

import SwiftUI

// MARK: - ViewModels

@MainActor @Observable
final class PlayerViewModel {
    init(itemID: String, jellyfinService: JellyfinService) {}
}

// MARK: - Views

struct PlayerView: View {
    @Bindable var viewModel: PlayerViewModel

    var body: some View {
        Text("Player")
    }
}
