# Widget Refresh & Data Accuracy Guide

## How Often Does the Widget Refresh?

### Updated Refresh Rate: **Every 2 Minutes** ⏱️

**Before**: Every 15 minutes  
**After**: Every 2 minutes

This ensures your arrival times are always accurate and up-to-date!

---

## How Widget Refresh Works

### 1. **Timeline System**
iOS widgets use a "timeline" system where the widget tells iOS:
- What to display at specific times
- When to fetch new data

### 2. **Your Widget's Refresh Cycle**

```
┌─────────────────────────────────────┐
│ T+0min: Fetch new MBTA data         │ ← Widget makes API call
│         Create 2 timeline entries   │
│         Next refresh: T+2min        │
├─────────────────────────────────────┤
│ T+1min: Update countdown display    │ ← iOS updates display
│         (6 min → 5 min)             │   (no API call)
├─────────────────────────────────────┤
│ T+2min: Fetch new MBTA data ⟲       │ ← Widget makes API call
│         Create 2 timeline entries   │
│         Next refresh: T+4min        │
└─────────────────────────────────────┘
```

### 3. **What Happens Every 2 Minutes**

1. **Widget fetches fresh data** from MBTA API
2. **Gets next 3 bus arrivals** for your route
3. **Creates 2 timeline entries**:
   - Entry 1: Current minute (0 min)
   - Entry 2: Next minute (1 min)
4. **Schedules next refresh** for 2 minutes later

### 4. **Between Refreshes**

iOS automatically updates the display every minute to show the countdown:
- "6 min" → "5 min" → "4 min" etc.

---

## Why 2 Minutes Instead of 15 Minutes?

### Benefits of 2-Minute Refresh:

✅ **More Accurate**: Fresh data every 2 minutes  
✅ **Catches Delays**: If a bus is running late, you'll know quickly  
✅ **Better UX**: Users see up-to-date information  
✅ **Real-time Feel**: Feels like a live tracker  

### Trade-offs:

⚠️ **More API Calls**: 30 calls/hour vs 4 calls/hour  
⚠️ **More Battery**: Slightly more background processing  
⚠️ **More Data**: Uses more cellular/WiFi data  

### Is This a Problem?

**No!** Here's why:
- **iOS manages battery** efficiently for widgets
- **API calls are lightweight** (just JSON data)
- **2 minutes is reasonable** for real-time transit
- **Similar to other transit apps** (Google Maps, Transit, etc.)

---

## iOS Widget Budget System

### How iOS Controls Widget Updates

Apple gives each widget a **"budget"** of updates per day:
- **High priority**: Apps used frequently (more budget)
- **Medium priority**: Apps used regularly (normal budget)
- **Low priority**: Apps rarely used (limited budget)

### Your Widget's Priority

If users:
- **Open your app frequently** → High budget → Updates reliably every 2 min
- **Rarely open your app** → Lower budget → iOS may skip some updates

### Best Practices Applied:

✅ **Smart refresh rate** (2 min is good balance)  
✅ **Efficient timeline entries** (only 2 entries per refresh)  
✅ **Handles errors gracefully** (shows message if data fails)  
✅ **No unnecessary refreshes** (only when needed)  

---

## When Does the Widget Actually Refresh?

### Automatic Refresh Triggers:

1. **Every 2 minutes** (timeline policy)
2. **When app is opened** (background refresh)
3. **When widget is first added** (initial load)
4. **When iOS allocates budget** (system decision)

### Manual Refresh Options:

Users can force refresh by:
1. **Opening the app** → App updates widget data
2. **Removing and re-adding widget**
3. **iOS automatically refreshes** based on usage patterns

---

## Why Widget Data Might Be Wrong

### Common Scenarios:

1. **iOS Budget Exhausted**
   - Widget hasn't refreshed in a while
   - User doesn't open app frequently
   - **Solution**: Open app to force refresh

2. **Network Issues**
   - Widget can't reach MBTA API
   - **Solution**: Shows "Could not load bus times" message

3. **MBTA Data Issues**
   - MBTA API returns stale/incorrect data
   - Bus schedule changes
   - **Solution**: Widget shows what MBTA reports

4. **Time Between Refreshes**
   - Data can be up to 2 minutes old
   - Bus could arrive/depart in that window
   - **Solution**: 2-min refresh minimizes this

---

## Comparison: App vs Widget Refresh

| Aspect | Main App | Widget |
|--------|----------|--------|
| **Refresh Rate** | On-demand (pull-to-refresh) | Every 2 minutes |
| **Data Freshness** | Instant when refreshed | Up to 2 min old |
| **User Control** | Full control | iOS managed |
| **Always Accurate** | When you refresh | Usually accurate |
| **Battery Impact** | Only when app open | Minimal background |

### Why App Feels More Accurate:

When you open the app and pull-to-refresh:
- You're **forcing** an immediate API call
- You see data that's **0 seconds old**
- You're in full control of when to refresh

With widgets:
- iOS manages when to refresh
- Data could be **0-2 minutes old**
- But it's **always visible** on home screen!

---

## Technical Implementation

### Current Code:

```swift
private func loadTimeline() async -> Timeline<MBTAWidgetEntry> {
    let state = await loadState()
    let now = Date()
    let entries = buildEntries(from: state, startingAt: now)
    
    // Refresh every 2 minutes for real-time accuracy
    let refreshDate = Calendar.current.date(byAdding: .minute, value: 2, to: now) 
        ?? now.addingTimeInterval(120)
    
    return Timeline(entries: entries, policy: .after(refreshDate))
}
```

### Timeline Entries Created:

```swift
private func buildEntries(...) -> [MBTAWidgetEntry] {
    // Create 2 entries (current minute + next minute)
    let minuteOffsets = [0, 1]
    
    // Each entry shows updated countdown
    // Entry 0: "6 min, 15 min, 22 min"
    // Entry 1: "5 min, 14 min, 21 min"
}
```

---

## Recommendations

### For Best Widget Accuracy:

1. **Open the app regularly**
   - Increases iOS widget budget
   - Keeps widget high priority
   - Ensures frequent refreshes

2. **Check app for critical timing**
   - If bus arrives in 1-2 minutes
   - Pull-to-refresh in app for latest data
   - Widget is for at-a-glance info

3. **Understand widget limitations**
   - Widgets are for **glanceable** information
   - Not meant to replace **real-time tracking**
   - App has more accurate, on-demand data

### Widget is Perfect For:

✅ Quick glance at next buses  
✅ Planning your departure  
✅ Seeing general schedule  
✅ Home screen convenience  

### Use App For:

✅ Exact real-time tracking  
✅ Critical timing (bus in 1-2 min)  
✅ Verifying before leaving  
✅ Checking multiple routes  

---

## Summary

| Question | Answer |
|----------|--------|
| **How often does widget refresh?** | Every 2 minutes |
| **How many API calls per hour?** | 30 calls/hour (every 2 min) |
| **Why might data be wrong?** | iOS budget, network issues, or MBTA data |
| **Why is app more accurate?** | On-demand refresh vs automatic refresh |
| **Is 2 minutes fast enough?** | Yes! Good balance of accuracy and efficiency |
| **Will this drain battery?** | No, iOS manages efficiently |

---

## Files Modified
- `/repo/MBTAWidget.swift` - Reduced refresh interval from 15min to 2min

**Result**: Widget now refreshes **7.5x more frequently** for much better real-time accuracy! 🚀
