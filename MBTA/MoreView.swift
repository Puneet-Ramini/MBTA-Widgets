//
//  MoreView.swift
//  MBTA
//
//  More tab with app info, feedback, and support tiles.
//

import SwiftUI
import AppIntents


struct MoreView: View {
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection

                    // Instructions
                    NavigationLink(destination: InstructionsView()) {
                        tileRow(icon: "book.fill", iconColor: .orange, title: "Instructions", trailing: .chevron)
                    }
                    .buttonStyle(.plain)

                    // About this app
                    Button {
                        haptic()
                        if let url = URL(string: "https://mbta-widgets.web.app") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        tileRow(icon: "app.fill", iconColor: .green, title: "About this app", trailing: .external)
                    }
                    .buttonStyle(.plain)

                    // Share Feedback
                    Button {
                        haptic()
                        if let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSetMU7XgiDaOgMJXtlMQVteH796sDNcNeviN-cikIC2CuRFAA/viewform?usp=header") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        tileRow(icon: "envelope.fill", iconColor: .blue, title: "Share Feedback", trailing: .external)
                    }
                    .buttonStyle(.plain)

                    // Privacy Policy
                    Button {
                        haptic()
                        if let url = URL(string: "https://mbta-widgets.web.app/privacy.html") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        tileRow(icon: "hand.raised.fill", iconColor: .purple, title: "Privacy Policy", trailing: .external)
                    }
                    .buttonStyle(.plain)

                    // Buy me a subway ride
                    Button {
                        haptic()
                        if let url = URL(string: "https://www.buymeacoffee.com/puneetramini") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("\u{1F687}")
                                .font(.system(size: 16))
                                .frame(width: 28, height: 28)

                            Text("Buy me a subway ride")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(red: 255/255, green: 221/255, blue: 0/255).opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(red: 255/255, green: 221/255, blue: 0/255).opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    // Add to Siri Shortcuts
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                        .tint(.cyan)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("More")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("App info, feedback & support")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.top, 8)
    }

    // MARK: - Tile Components

    private enum TrailingIcon {
        case chevron, external
    }

    private func tileRow(icon: String, iconColor: Color, title: String, trailing: TrailingIcon) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: trailing == .chevron ? "chevron.right" : "arrow.up.forward")
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

}

#Preview {
    MoreView()
        .preferredColorScheme(.dark)
}
