# Small Favorite Widgets - Implementation Summary

## Overview
Added two new small square widgets that display arrival times for Favorites 1 and 2, showing a compact view without the stop name.

## Changes Made

### 1. MBTAWidget.swift
Added three new components:

#### SmallFavoriteWidgetProvider
- A timeline provider that supports showing a specific favorite (by index)
- Loads the favorite from the app group UserDefaults
- Fetches predictions for that favorite's route/stop
- Shows only the next 2 arrivals (instead of 3 for the medium widget)
- Refreshes every 2 minutes like the main widget

#### SmallFavoriteWidgetView
- Compact view designed for the systemSmall widget size
- Displays:
  - Route number badge (yellow background)
  - Direction text (e.g., "To Back Bay Station")
  - 2 arrival time pills showing minutes
- No stop name (as requested)
- No "stops away" information (keeps it clean for small size)

#### Two Widget Definitions
- **SmallFavorite1Widget**: Shows Favorite 1 arrivals
- **SmallFavorite2Widget**: Shows Favorite 2 arrivals

#### Updated Widget Bundle
Now exports all three widgets:
- `MBTAWidget` (existing medium-sized widget)
- `SmallFavorite1Widget` (new)
- `SmallFavorite2Widget` (new)

### 2. ArrivalsViewModel.swift
Updated `saveQuickRoutes()` method to:
- Save favorites to app group UserDefaults (in addition to standard UserDefaults)
- Reload widget timelines when favorites are updated
- Key: "quickFavorites" in the app group contains all 4 favorites as JSON array

### 3. ContentView.swift
Updated the widget instructions section to:
- Explain the three different widget options available
- Clarify which widget does what:
  - Long tile: Full customizable widget with time overrides
  - Small square "Favorite 1": Quick access to Favorite 1
  - Small square "Favorite 2": Quick access to Favorite 2

## Widget Examples

### Example 1: Favorite 1 Widget
```
┌─────────────────┐
│  39             │  ← Yellow badge
│  To Back Bay    │  ← Direction
│  Station        │
│                 │
│  ┌───────────┐  │
│  │  2 min    │  │  ← First arrival
│  └───────────┘  │
│  ┌───────────┐  │
│  │  4 min    │  │  ← Second arrival
│  └───────────┘  │
└─────────────────┘
```

### Example 2: Favorite 2 Widget
```
┌─────────────────┐
│  CT2            │  ← Yellow badge
│  To Sullivan    │  ← Direction
│  Square         │
│                 │
│  ┌───────────┐  │
│  │  5 min    │  │  ← First arrival
│  └───────────┘  │
│  ┌───────────┐  │
│  │  12 min   │  │  ← Second arrival
│  └───────────┘  │
└─────────────────┘
```

## How It Works

1. **User sets up favorites in the app** using the Quick Access buttons
2. **Favorites are saved** to both:
   - Standard UserDefaults (for app use)
   - App Group UserDefaults (for widget access)
3. **User adds widgets** to their home screen:
   - Long press home screen
   - Tap Edit → Add Widget
   - Search "MBTA"
   - Choose "Favorite 1" or "Favorite 2" small widget
4. **Widgets auto-refresh** every 2 minutes with live arrival data
5. **Widgets automatically reload** when favorites are updated in the app

## Technical Details

### Data Flow
```
App (ContentView)
    ↓
ArrivalsViewModel.saveFavorite()
    ↓
saveQuickRoutes()
    ↓ (saves to both)
    ├─→ UserDefaults.standard (for app)
    └─→ UserDefaults(suiteName: "group.Widgets.MBTA") (for widgets)
        ↓
SmallFavoriteWidgetProvider.loadFavorite()
    ↓
Widget displays arrivals
```

### Widget Sizes
- **Main widget**: `.systemMedium` (long rectangular tile)
- **Favorite widgets**: `.systemSmall` (small square tile)

### API Usage
Each small widget makes its own API calls:
- `/predictions` endpoint (every 2 minutes per widget)
- Same rate limiting and error handling as main widget
- Recorded in the API usage tracker

## Testing
Previews are available in Xcode for both widgets:
- Preview "Favorite 1"
- Preview "Favorite 2"

## Future Enhancements
Potential improvements:
- Allow users to choose which favorite index each widget shows (instead of fixed 1 and 2)
- Add a third small widget for Favorite 3
- Add color coding based on time urgency (red if <2 min, etc.)
- Show "Arriving" instead of "0 min"
