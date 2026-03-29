// Finn/Placeholders.swift
// Temporary stubs — will be replaced by real implementations

import SwiftUI

// MARK: - ViewModels

@MainActor @Observable
final class MovieDetailViewModel {
    init(itemID: String, jellyfinService: JellyfinService) {}
}

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

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Text("Home")
    }
}

struct MovieDetailView: View {
    @Bindable var viewModel: MovieDetailViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Text("Movie Detail")
    }
}

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
