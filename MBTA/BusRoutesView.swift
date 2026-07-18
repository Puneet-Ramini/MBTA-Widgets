//
//  BusRoutesView.swift
//  MBTA
//
//  Dedicated bus route selection page with grid of all routes,
//  live search, and system map link.
//

import SwiftUI

struct BusRoutesView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
    private let busYellow = Color(red: 255/255, green: 200/255, blue: 0/255)

    private var filteredRoutes: [Route] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.allBusRoutes }
        return viewModel.allBusRoutes.filter { route in
            let name = route.displayName.lowercased()
            let id = route.id.lowercased()
            let longName = (route.longName ?? "").lowercased()
            return name.hasPrefix(query) || id.hasPrefix(query) ||
                   name.contains(query) || longName.contains(query)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                searchBar
                allRoutesGrid
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Search")
                            .font(.system(size: 17))
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("MBTABus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 140)

            VStack(alignment: .leading, spacing: 4) {
                Text("Bus")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)

                Text("Find your bus route")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))

                Text("Select a route to continue")
                    .font(.system(size: 14))
                    .foregroundColor(busYellow)
            }

            Spacer()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.35))

            TextField("Search routes...", text: $searchText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(white: 0.20), lineWidth: 1)
                )
        )
    }

    // MARK: - All Routes Grid

    private var allRoutesGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("All Bus Routes")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            if filteredRoutes.isEmpty {
                HStack {
                    Spacer()
                    Text("No routes found")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredRoutes) { route in
                        Button {
                            haptic(.medium)
                            selectRoute(route)
                        } label: {
                            Text(route.displayName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(busYellow)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func selectRoute(_ route: Route) {
        viewModel.selectedMode = .bus
        Task {
            await viewModel.selectSuggestedRoute(route)
        }
        dismiss()
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#Preview {
    NavigationStack {
        BusRoutesView(viewModel: ArrivalsViewModel())
    }
    .preferredColorScheme(.dark)
}
