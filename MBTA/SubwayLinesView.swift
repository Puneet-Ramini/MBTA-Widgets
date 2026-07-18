//
//  SubwayLinesView.swift
//  MBTA
//
//  Dedicated subway line selection page with line cards.
//

import SwiftUI

struct SubwayLinesView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingGreenBranches = false

    private let subwayYellow = Color(red: 255/255, green: 200/255, blue: 0/255)

    private struct SubwayLine: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let badgeText: String
        let badgeColor: Color
        let badgeTextColor: Color
        let query: String
        let isGreenLine: Bool

        init(id: String, name: String, subtitle: String, badgeText: String,
             badgeColor: Color, badgeTextColor: Color = .white,
             query: String, isGreenLine: Bool = false) {
            self.id = id
            self.name = name
            self.subtitle = subtitle
            self.badgeText = badgeText
            self.badgeColor = badgeColor
            self.badgeTextColor = badgeTextColor
            self.query = query
            self.isGreenLine = isGreenLine
        }
    }

    private let lines: [SubwayLine] = [
        SubwayLine(id: "red", name: "Red Line", subtitle: "Braintree / Ashmont",
                   badgeText: "RL",
                   badgeColor: Color(red: 218/255, green: 41/255, blue: 28/255),
                   query: "Red"),
        SubwayLine(id: "orange", name: "Orange Line", subtitle: "Oak Grove / Forest Hills",
                   badgeText: "OL",
                   badgeColor: Color(red: 237/255, green: 139/255, blue: 0/255),
                   query: "Orange"),
        SubwayLine(id: "blue", name: "Blue Line", subtitle: "Wonderland / Bowdoin",
                   badgeText: "BL",
                   badgeColor: Color(red: 0/255, green: 115/255, blue: 207/255),
                   query: "Blue"),
        SubwayLine(id: "green", name: "Green Line", subtitle: "All Branches",
                   badgeText: "BCDE",
                   badgeColor: Color(red: 0/255, green: 132/255, blue: 61/255),
                   query: "Green", isGreenLine: true),
        SubwayLine(id: "mattapan", name: "Mattapan Line", subtitle: "Ashmont / Mattapan",
                   badgeText: "M",
                   badgeColor: .purple,
                   query: "Mattapan")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                lineCardsSection
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
        .navigationDestination(isPresented: $isShowingGreenBranches) {
            GreenLineBranchesView(viewModel: viewModel)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("MBTASubway")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 110)

            VStack(alignment: .leading, spacing: 4) {
                Text("Subway")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Choose a subway line")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))

                Text("Select a line to continue")
                    .font(.system(size: 14))
                    .foregroundColor(subwayYellow)
            }

            Spacer()
        }
    }

    // MARK: - Line Cards

    private var lineCardsSection: some View {
        VStack(spacing: 10) {
            ForEach(lines) { line in
                Button {
                    haptic(.medium)
                    selectLine(line)
                } label: {
                    lineCard(line)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func lineCard(_ line: SubwayLine) -> some View {
        HStack(spacing: 12) {
            // Badge
            lineBadge(line)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(line.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(line.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

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

    @ViewBuilder
    private func lineBadge(_ line: SubwayLine) -> some View {
        if line.isGreenLine {
            HStack(spacing: 3) {
                ForEach(["B", "C", "D", "E"], id: \.self) { branch in
                    Text(branch)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(line.badgeColor))
                }
            }
        } else {
            Text(line.badgeText)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(line.badgeTextColor)
                .frame(width: 42, height: 42)
                .background(Circle().fill(line.badgeColor))
        }
    }

    // MARK: - Helpers

    private func selectLine(_ line: SubwayLine) {
        if line.isGreenLine {
            isShowingGreenBranches = true
        } else {
            viewModel.selectedMode = .subway
            viewModel.selectPresetLine(PresetLine(title: line.name, query: line.query, colorName: ""))
            Task {
                await viewModel.loadRoute()
            }
            dismiss()
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#Preview {
    NavigationStack {
        SubwayLinesView(viewModel: ArrivalsViewModel())
    }
    .preferredColorScheme(.dark)
}
