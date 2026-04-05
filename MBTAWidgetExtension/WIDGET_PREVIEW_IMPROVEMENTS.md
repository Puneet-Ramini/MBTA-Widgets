# Widget Preview & Gallery Improvements

## Problem
When users go to add the widget from the widget gallery, they see either:
- An empty/blank widget (if no favorite is configured)
- A message saying "Open the app and choose..."

This doesn't give users a good preview of what the widget will look like with actual data.

## Solution
Updated the widget to **always show a beautiful preview** in the widget gallery, regardless of whether the user has configured a favorite or not.

## Changes Made

### 1. Updated `placeholder()` Function
The placeholder now shows sample MBTA data:
- **Route**: 39
- **Direction**: To Back Bay Station
- **Stop**: Huntington Ave @ Perkins St
- **Arrival Times**: 6 min, 15 min, 22 min
- **Stops Away**: 2, 5, 8 stops away

This gives users a clear idea of what the widget will display.

### 2. Enhanced `getSnapshot()` Function
The snapshot function now handles two contexts:

**In Widget Gallery (Preview Mode)**:
```swift
if context.isPreview {
    completion(placeholder(in: context))
}
```
Always shows the nice sample data preview.

**On Home Screen**:
```swift
else {
    Task {
        let state = await loadState()
        let entry = buildPreviewEntry(from: state)
        completion(entry)
    }
}
```
Shows actual user data if configured, or setup message if not.

### 3. Added Helper Functions
- `buildPreviewEntry()` - Converts widget state to entry
- `formatMinutes()` - Formats arrival times as "6 min" or "Now"

### 4. Added Xcode Preview
Added a preview at the bottom of the file so developers can see the widget in Xcode canvas:
```swift
#Preview(as: .systemMedium) {
    MBTAWidget()
} timeline: {
    // Sample entries with live data
}
```

## User Experience Flow

### Before Installing Widget
**Widget Gallery View**:
```
┌──────────────────────────────┐
│ 39  To Back Bay Station      │
│     Huntington Ave            │
│                               │
│ 6 min    15 min    22 min    │
│ 2 stops  5 stops   8 stops   │
│                               │
└──────────────────────────────┘
```
✨ Users see exactly what the widget will look like!

### After Installing (No Favorite Set)
**On Home Screen**:
```
┌──────────────────────────────┐
│ --  Pick a route in the app  │
│                               │
│ Open the app and choose a    │
│ bus, direction, and stop.    │
│                               │
└──────────────────────────────┘
```
Clear call-to-action to configure.

### After Installing (With Favorite)
**On Home Screen**:
```
┌──────────────────────────────┐
│ 39  To Back Bay Station      │
│     Ruggles Station           │
│                               │
│ 12 min   18 min   25 min     │
│ 3 stops  6 stops   9 stops   │
│                               │
└──────────────────────────────┘
```
Shows real-time arrival data!

## Benefits

1. **Better First Impression**: Users see an attractive, data-filled preview in the widget gallery
2. **Clear Value Proposition**: Shows exactly what information the widget provides
3. **Professional Appearance**: No more blank/empty previews
4. **Encourages Installation**: Users know what they're getting before adding
5. **Matches Apple Guidelines**: Proper use of placeholder and snapshot contexts

## Technical Details

### Widget Context Types
- `context.isPreview` - Widget gallery, widget configuration screen
- Regular context - Actual widget on home screen

### Timeline Updates
The widget still:
- Refreshes every 15 minutes
- Shows real-time data when configured
- Handles errors gracefully
- Works with widget customization features

## Files Modified
- `/repo/MBTAWidget.swift` - Widget provider preview logic

---

**Result**: Users now see a beautiful, professional preview of the widget in the widget gallery, encouraging them to install it! 🎉
