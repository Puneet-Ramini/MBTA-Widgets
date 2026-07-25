//
//  GreenLineBranchesView.swift
//  MBTA
//
//  Green Line branch selection page — user picks B, C, D, or E
//  before continuing into the existing direction/stop flow.
//

import SwiftUI

struct GreenLineBranchesView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @Environment(\.dismiss) private var dismiss

    private let greenColor = Color(red: 0/255, green: 132/255, blue: 61/255)
    private let subwayYellow = Color(red: 255/255, green: 200/255, blue: 0/255)

    private struct Branch: Identifiable {
        let id: String
        let letter: String
        let name: String
        let subtitle: String
        let query: String
    }

    private let branches: [Branch] = [
        Branch(id: "B", letter: "B", name: "Green Line B",
               subtitle: "Boston College / Government Center", query: "Green-B"),
        Branch(id: "C", letter: "C", name: "Green Line C",
               subtitle: "Cleveland Circle / Government Center", query: "Green-C"),
        Branch(id: "D", letter: "D", name: "Green Line D",
               subtitle: "Riverside / Union Square", query: "Green-D"),
        Branch(id: "E", letter: "E", name: "Green Line E",
               subtitle: "Heath Street / Medford/Tufts", query: "Green-E")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                branchCards
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
                        Text("Subway")
                            .font(.system(size: 17))
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("MBTASubway")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text("Green Line")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)

                Text("Choose a branch")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))

                Text("Select a branch to continue")
                    .font(.system(size: 14))
                    .foregroundColor(subwayYellow)
            }

            Spacer()
        }
    }

    // MARK: - Branch Cards

    private var branchCards: some View {
        VStack(spacing: 10) {
            ForEach(branches) { branch in
                Button {
                    haptic(.medium)
                    selectBranch(branch)
                } label: {
                    branchCard(branch)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func branchCard(_ branch: Branch) -> some View {
        HStack(spacing: 12) {
            // Badge
            Text(branch.letter)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(greenColor))

            // Title + subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(branch.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(branch.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

            // Small subway image
            Image("MBTASubway")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56)
                .opacity(0.8)

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
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

    // MARK: - Helpers

    private func selectBranch(_ branch: Branch) {
        viewModel.selectedMode = .subway
        viewModel.selectPresetLine(PresetLine(title: "Green Line", query: "Green", colorName: "green"))
        viewModel.selectGreenBranch(PresetLine(title: branch.letter, query: branch.query, colorName: "green"))
        Task {
            await viewModel.loadRoute()
        }
        // Don't dismiss here — ContentView's onChange(of: viewModel.directions)
        // will dismiss the entire SubwayLines → GreenBranches navigation stack at once
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#Preview {
    NavigationStack {
        GreenLineBranchesView(viewModel: ArrivalsViewModel())
    }
    .preferredColorScheme(.dark)
}
