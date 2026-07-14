//
//  WidgetsView.swift
//  MBTA
//
//  Widgets tab: shows widget preview, list of configured widgets, and time override.
//

import SwiftUI
import WidgetKit

struct WidgetsView: View {
    @ObservedObject var viewModel: ArrivalsViewModel
    
    private let accentPink = Color(red: 232/255, green: 54/255, blue: 101/255)
    private let cardBackground = Color(white: 0.12)
    private let cardBorder = Color(white: 0.20)
    private let widgetBlue = Color(red: 0/255, green: 57/255, blue: 166/255)
    private let busYellow = Color(red: 255/255, green: 200/255, blue: 0/255)
    private let greenLine = Color(red: 0/255, green: 132/255, blue: 61/255)
    
    private var savedFavorites: [SavedFavorite] {
        viewModel.quickFavorites.compactMap { $0 }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if savedFavorites.isEmpty {
                        headerOnly
                        emptyState
                    } else {
                        topHeroSection
                        yourWidgetsSection
                        timeOverrideRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                autoAssignWidgets()
            }
        }
    }
    
    // MARK: - Header Only (empty state)
    
    private var headerOnly: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widgets")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            
            Text("Stay updated with your favorite routes, right from your home screen.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.25))
            
            Text("No widgets configured")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("Please add a favorite first.\nSave a shortcut from the Home or Search tab to automatically configure your widgets.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Top Hero Section
    
    private var topHeroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                // Left: title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Widgets")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Stay updated with your favorite routes, right from your home screen.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Right: hardcoded medium widget preview (white bg)
                heroWidgetPreview
                    .frame(width: 165)
            }
            
            // Caption
            HStack {
                Spacer()
                Text("This is how it appears on\nyour Home Screen")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.trailing)
                    .italic()
            }
        }
    }
    
    // MARK: - Hero Widget Preview (hardcoded from screenshot — medium widget, white bg)
    
    private var heroWidgetPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: yellow 39 badge + "To Back Bay Station"
            HStack(alignment: .top, spacing: 8) {
                Text("39")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(busYellow)
                    )
                
                Text("To Back Bay Station")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(2)
            }
            
            Spacer().frame(height: 0)
            
            // Row 2: three blue pills — 7 min, 4 min, 11 min
            HStack(spacing: 5) {
                ForEach(["7 min", "4 min", "11 min"], id: \.self) { text in
                    Text(text)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(widgetBlue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
        )
    }
    
    // MARK: - Your Widgets Section
    
    private var yourWidgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Widgets")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            // Wide Widget — hardcoded: 39 to Back Bay Station
            wideWidgetRow
            
            // Small Widget 1 — hardcoded: E to Medford/Tufts
            smallWidget1Row
            
            // Small Widget 2 — hardcoded: 1 to Harvard Square
            smallWidget2Row
        }
    }
    
    // MARK: - Wide Widget Row (hardcoded from screenshot)
    
    private var wideWidgetRow: some View {
        HStack(spacing: 12) {
            // Blue dot
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
            
            // Mini medium widget preview (white bg)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Text("39")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(busYellow)
                        )
                    
                    Text("To Back Bay Station")
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(2)
                }
                
                Text("Huntington Ave @ Perkins St")
                    .font(.system(size: 5))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                // Mini blue pills
                HStack(spacing: 2) {
                    ForEach(["7", "4", "11"], id: \.self) { t in
                        Text(t)
                            .font(.system(size: 5, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(widgetBlue)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(5)
            .frame(width: 90, height: 55, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
            )
            
            // Info text
            VStack(alignment: .leading, spacing: 3) {
                Text("Wide Widget")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("39 • Back Bay Station")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                
                Text("Huntington Ave @ Perkins St")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Small Widget 1 Row (hardcoded from screenshot)
    
    private var smallWidget1Row: some View {
        HStack(spacing: 12) {
            // Green dot
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
            
            // Mini small widget preview (white bg)
            VStack(alignment: .leading, spacing: 3) {
                Text("E")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(greenLine)
                    )
                
                Text("To Medford/Tufts")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(2)
            }
            .padding(5)
            .frame(width: 65, height: 55, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
            )
            
            // Info text
            VStack(alignment: .leading, spacing: 3) {
                Text("Small Widget 1")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("E • Medford/Tufts")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                
                Text("Heath Street")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Small Widget 2 Row (hardcoded from screenshot)
    
    private var smallWidget2Row: some View {
        HStack(spacing: 12) {
            // Orange dot
            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)
            
            // Mini small widget preview (white bg)
            VStack(alignment: .leading, spacing: 3) {
                Text("1")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(busYellow)
                    )
                
                Text("To Harvard Square")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(2)
                
                Text("Massachusetts Ave @\nSt Botolph St")
                    .font(.system(size: 5))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            .padding(5)
            .frame(width: 65, height: 55, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
            )
            
            // Info text
            VStack(alignment: .leading, spacing: 3) {
                Text("Small Widget 2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("1 • Harvard Square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                
                Text("Massachusetts Ave @ St Botolph St")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Time Override Row
    
    private var timeOverrideRow: some View {
        NavigationLink {
            WidgetCustomizationView(viewModel: viewModel)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 20))
                    .foregroundColor(accentPink)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Override")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Set specific times for a different route")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Auto Assignment
    
    private func autoAssignWidgets() {
        guard let defaults = UserDefaults(suiteName: "group.Widgets.MBTA") else { return }
        
        var changed = false
        
        if viewModel.quickFavorites[safe: 0] != nil {
            if defaults.object(forKey: "mediumWidgetFavoriteIndex") as? Int != 0 {
                defaults.set(0, forKey: "mediumWidgetFavoriteIndex")
                changed = true
            }
        }
        
        if viewModel.quickFavorites[safe: 1] != nil {
            if defaults.object(forKey: "smallWidget1FavoriteIndex") as? Int != 1 {
                defaults.set(1, forKey: "smallWidget1FavoriteIndex")
                changed = true
            }
        }
        
        if viewModel.quickFavorites[safe: 2] != nil {
            if defaults.object(forKey: "smallWidget2FavoriteIndex") as? Int != 2 {
                defaults.set(2, forKey: "smallWidget2FavoriteIndex")
                changed = true
            }
        }
        
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    WidgetsView(viewModel: ArrivalsViewModel())
        .preferredColorScheme(.dark)
}
