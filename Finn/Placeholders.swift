// Finn/Placeholders.swift
// Temporary stubs — will be replaced by real implementations

import SwiftUI

// MARK: - ViewModels

@MainActor @Observable
final class SeriesDetailViewModel {
    init(itemID: String, jellyfinService: JellyfinService) {}
}

@MainActor @Observable
final class PlayerViewModel {
    init(itemID: String, jellyfinService: JellyfinService) {}
}

@MainActor @Observable
final class SearchViewModel {
    init(jellyfinService: JellyfinService) {}
}

// MARK: - Views

struct SeriesDetailView: View {
    @Bindable var viewModel: SeriesDetailViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Text("Series Detail")
    }
}

struct PlayerView: View {
    @Bindable var viewModel: PlayerViewModel

    var body: some View {
        Text("Player")
    }
}

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Text("Search")
    }
}
