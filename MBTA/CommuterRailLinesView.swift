//
//  CommuterRailLinesView.swift
//  MBTA
//
//  Dedicated commuter rail line selection page with line cards.
//

import SwiftUI

struct CommuterRailLinesView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    @Environment(\.dismiss) private var dismiss

    private let crYellow = Color(red: 255/255, green: 200/255, blue: 0/255)
    private let crPurple = Color.purple

    private struct CRLine: Identifiable {
        let id: String
        let name: String
        let query: String
    }

    private let lines: [CRLine] = [
        CRLine(id: "fairmount", name: "Fairmount", query: "Fairmount"),
        CRLine(id: "fall-river", name: "Fall River / New Bedford", query: "Fall River/New Bedford"),
        CRLine(id: "fitchburg", name: "Fitchburg", query: "Fitchburg"),
        CRLine(id: "framingham", name: "Framingham / Worcester", query: "Framingham/Worcester"),
        CRLine(id: "franklin", name: "Franklin / Foxboro", query: "Franklin/Foxboro"),
        CRLine(id: "greenbush", name: "Greenbush", query: "Greenbush"),
        CRLine(id: "haverhill", name: "Haverhill", query: "Haverhill"),
        CRLine(id: "kingston", name: "Kingston", query: "Kingston"),
        CRLine(id: "lowell", name: "Lowell", query: "Lowell"),
        CRLine(id: "needham", name: "Needham", query: "Needham"),
        CRLine(id: "newburyport", name: "Newburyport / Rockport", query: "Newburyport/Rockport"),
        CRLine(id: "providence", name: "Providence / Stoughton", query: "Providence/Stoughton")
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
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("MBTACommuterRailHeader")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text("Commuter Rail")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text("Choose a line")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))

                Text("Select a line to continue")
                    .font(.system(size: 14))
                    .foregroundColor(crYellow)
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

    private func lineCard(_ line: CRLine) -> some View {
        HStack(spacing: 12) {
            // Badge
            Text("CR")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(crPurple))

            // Title
            Text(line.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

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

    // MARK: - Helpers

    private func selectLine(_ line: CRLine) {
        viewModel.selectedMode = .commuterRail
        viewModel.selectPresetLine(PresetLine(title: line.name, query: line.query, colorName: "purple"))
        Task {
            await viewModel.loadRoute()
        }
        dismiss()
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#Preview {
    NavigationStack {
        CommuterRailLinesView(viewModel: ArrivalsViewModel())
    }
    .preferredColorScheme(.dark)
}
