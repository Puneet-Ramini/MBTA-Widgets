# 🧪 Supabase Integration Testing Guide

## Testing Checklist

Use this guide to verify your Supabase integration is working correctly.

---

## Pre-Testing Setup

### ✅ Prerequisites

Before testing, make sure you've completed:

- [ ] Added Supabase Swift package to Xcode
- [ ] Run SQL schema in Supabase dashboard
- [ ] App builds without errors
- [ ] Can see cloud button (☁️) in app

---

## Level 1: Basic Connection Tests

### Test 1.1: Open Settings View

**Steps:**
1. Launch app
2. Tap cloud icon (☁️) in top right

**Expected Result:**
- ✅ Settings view opens
- ✅ Shows "Not Connected" status (red)
- ✅ No crashes

**If Failed:**
- Check that `SupabaseSettingsView.swift` was added to target
- Rebuild project (Cmd+B)

---

### Test 1.2: Anonymous Sign-In

**Steps:**
1. Open Supabase settings (cloud button)
2. Tap "Sign In Anonymously"
3. Wait 2-3 seconds

**Expected Result:**
- ✅ Button becomes disabled during loading
- ✅ Success message appears: "Successfully signed in anonymously!"
- ✅ Status changes to "Connected" (green)
- ✅ User ID is displayed (long UUID string)

**If Failed:**
- Check internet connection
- Verify Supabase URL in `SupabaseConfig.swift`
- Check Supabase dashboard is accessible
- Look for error message in UI

**Debug:**
```swift
// Add to SupabaseService.swift signInAnonymously()
print("Attempting anonymous sign-in...")
print("URL: \(SupabaseConfig.url)")
```

---

### Test 1.3: Sign Out

**Steps:**
1. After signing in, scroll down
2. Tap "Sign Out" button

**Expected Result:**
- ✅ Status changes to "Not Connected" (red)
- ✅ User ID disappears
- ✅ Success message: "Signed out successfully!"
- ✅ Cloud favorites section disappears

**If Failed:**
- Check console for errors
- Try force-quitting app and relaunching

---

## Level 2: Database Tests

### Test 2.1: Load Empty Favorites

**Steps:**
1. Sign in anonymously (fresh account)
2. Tap "Load from Cloud"

**Expected Result:**
- ✅ Success message: "Loaded 0 favorites from cloud"
- ✅ Shows "No cloud favorites yet"
- ✅ No crashes or errors

**If Failed:**
- Verify SQL schema was run (check Supabase dashboard → Table Editor)
- Check that 'favorites' table exists
- Verify RLS policies are enabled

**Debug in Supabase Dashboard:**
1. Go to Table Editor
2. Click "favorites" table
3. Should see table with columns (might be empty)

---

### Test 2.2: Save a Favorite

**Steps:**
1. In main app, select:
   - Mode: Bus
   - Route: 39 (or any route)
   - Direction: Pick one
   - Stop: Pick one
2. Tap a "Quick Access" button
3. Choose "Favorite 1" or "Favorite 2"

**Expected Result:**
- ✅ Favorite saved locally (shows in button)
- ✅ No errors in console

**Manual Cloud Save Test:**
```swift
// Add this test in SupabaseSettingsView or run in Xcode playground
Task {
    let testFavorite = SavedFavorite(
        mode: .bus,
        routeID: "39",
        routeName: "39",
        directionID: 0,
        directionName: "Outbound",
        directionDestination: "Back Bay Station",
        stopID: "64",
        stopName: "Test Stop"
    )
    
    do {
        try await SupabaseService.shared.saveFavorite(testFavorite)
        print("✅ Save successful!")
    } catch {
        print("❌ Save failed: \(error)")
    }
}
```

---

### Test 2.3: Load Saved Favorites

**Steps:**
1. After saving a favorite (Test 2.2)
2. Open Supabase settings (cloud button)
3. Tap "Load from Cloud"

**Expected Result:**
- ✅ Success message: "Loaded 1 favorites from cloud"
- ✅ Favorite appears in list with:
  - Route name (e.g., "39")
  - Direction (e.g., "To Back Bay Station")
  - Stop name

**If Failed:**
- Check Supabase Table Editor to see if data was saved
- Verify user_id matches between save and load
- Check RLS policies allow SELECT

**Debug in Supabase:**
```sql
-- Run in SQL Editor to see all favorites
SELECT * FROM favorites;

-- See favorites for specific user
SELECT * FROM favorites
WHERE user_id = 'YOUR-USER-UUID-HERE';
```

---

### Test 2.4: Multiple Favorites

**Steps:**
1. Save 2-3 different favorites
2. Load from cloud

**Expected Result:**
- ✅ All favorites appear in list
- ✅ Count is accurate: "Loaded 3 favorites from cloud"
- ✅ Each has correct route, direction, stop

---

## Level 3: Email Authentication Tests (Optional)

### Test 3.1: Sign Up with Email

**Steps:**
1. Sign out if signed in
2. Enter email: `test@example.com`
3. Enter password: `password123`
4. Tap "Sign Up"

**Expected Result:**
- ✅ Success message: "Account created successfully!"
- ✅ Status shows "Connected"
- ✅ Email fields clear
- ✅ User ID displayed

**If Failed:**
- Email might already exist (try different email)
- Password might be too short (Supabase default: 6+ chars)
- Check Supabase Auth settings in dashboard

**Note:** By default, Supabase requires email confirmation. You can:
- **Option A:** Disable email confirmation in Supabase dashboard
  - Go to Authentication → Settings
  - Toggle off "Enable email confirmations"
- **Option B:** Check email for confirmation link

---

### Test 3.2: Sign In with Email

**Steps:**
1. Sign out
2. Enter same email from Test 3.1
3. Enter same password
4. Tap "Sign In"

**Expected Result:**
- ✅ Success message: "Signed in successfully!"
- ✅ Status shows "Connected"
- ✅ Previous favorites still available

---

## Level 4: Integration Tests

### Test 4.1: Auto Sign-In on Launch

**Steps:**
1. Add to `MBTAApp.swift`:
```swift
.task {
    try? await SupabaseService.shared.signInAnonymously()
}
```
2. Force quit app
3. Relaunch app
4. Open cloud settings immediately

**Expected Result:**
- ✅ Status shows "Connected" (no manual sign-in needed)
- ✅ User ID is displayed

---

### Test 4.2: Auto-Sync Favorites

**Steps:**
1. Add sync code to `ArrivalsViewModel.saveFavorite()`:
```swift
Task {
    try? await SupabaseService.shared.saveFavorite(favorite)
    print("✅ Synced to cloud")
}
```
2. Save a favorite in main app
3. Check cloud settings

**Expected Result:**
- ✅ Favorite appears in cloud list immediately
- ✅ Console shows: "✅ Synced to cloud"

---

### Test 4.3: Cross-Device Sync

**Steps:**
1. Sign in with email on Device A
2. Save favorite
3. Sign in with same email on Device B
4. Load from cloud

**Expected Result:**
- ✅ Favorite from Device A appears on Device B
- ✅ Both devices show same data

**Alternative Test (same device):**
1. Sign in with email
2. Save favorite
3. Delete app
4. Reinstall app
5. Sign in with same email
6. Load from cloud
- ✅ Favorite is restored

---

## Level 5: Error Handling Tests

### Test 5.1: No Internet Connection

**Steps:**
1. Turn on Airplane Mode
2. Try to sign in anonymously

**Expected Result:**
- ✅ Error message appears
- ✅ App doesn't crash
- ✅ Can retry after reconnecting

---

### Test 5.2: Invalid Credentials

**Steps:**
1. Try to sign in with:
   - Email: `fake@test.com`
   - Password: `wrongpassword`

**Expected Result:**
- ✅ Error message: "Failed to sign in: ..."
- ✅ Stays on sign-in screen
- ✅ Can try again

---

### Test 5.3: Database Not Available

**Steps:**
1. Temporarily pause Supabase project (in dashboard)
2. Try to load favorites

**Expected Result:**
- ✅ Error message appears
- ✅ App continues to work with local data
- ✅ No crashes

---

## Level 6: Performance Tests

### Test 6.1: Large Dataset

**Steps:**
1. Add 10+ favorites
2. Load from cloud
3. Measure time

**Expected Result:**
- ✅ Loads in < 2 seconds
- ✅ UI remains responsive
- ✅ No lag or freezing

---

### Test 6.2: Offline Operation

**Steps:**
1. Use app normally (save favorites locally)
2. Turn off internet
3. Continue using app

**Expected Result:**
- ✅ App works normally
- ✅ Favorites saved locally
- ✅ Cloud sync happens when back online

---

## Security Tests

### Test 7.1: User Isolation

**Steps:**
1. Sign in as User A
2. Save favorite "Route 39"
3. Sign out
4. Sign in as User B (different account)
5. Load favorites

**Expected Result:**
- ✅ User B sees ONLY their favorites
- ✅ User A's "Route 39" is NOT visible
- ✅ This confirms RLS is working!

**Debug in Supabase:**
```sql
-- As admin, you can see all data
SELECT user_id, route_name FROM favorites;

-- But users only see their own (RLS enforces this)
```

---

### Test 7.2: Unauthorized Access

**Steps:**
1. Sign out completely
2. Try to load favorites (should fail gracefully)

**Expected Result:**
- ✅ Error message or empty state
- ✅ Prompts to sign in
- ✅ No crashes

---

## API Logging Tests (Optional)

### Test 8.1: Log API Call

**Steps:**
1. Add to `MBTAService.swift` fetch method:
```swift
Task {
    try? await SupabaseService.shared.logAPIUsage(
        endpoint: "predictions",
        source: "app",
        statusCode: statusCode
    )
}
```
2. Make any MBTA API call in app
3. Check Supabase Table Editor → api_logs

**Expected Result:**
- ✅ New row in api_logs table
- ✅ Contains endpoint, source, status_code
- ✅ Timestamp is accurate

---

## Troubleshooting Failed Tests

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Cannot find Supabase" | Package not added | Add package via SPM |
| "Table doesn't exist" | SQL not run | Run `supabase_schema.sql` |
| "Not authenticated" | Not signed in | Sign in first |
| "RLS policy violation" | Wrong user_id | Check auth state |
| Network errors | Internet/URL | Check connection & config |
| "Email confirmation required" | Supabase setting | Disable or check email |

### Debug Checklist

If tests fail, check:
- [ ] Supabase project is active (not paused)
- [ ] API key is correct in `SupabaseConfig.swift`
- [ ] Internet connection is working
- [ ] Tables exist in Supabase dashboard
- [ ] RLS policies are enabled
- [ ] User is authenticated before DB operations
- [ ] Console logs show helpful error messages

### Getting More Info

Add debug logging:
```swift
// In SupabaseService.swift methods
print("🔵 [Supabase] Starting operation...")
print("🔵 [Supabase] User ID: \(currentUser?.id.uuidString ?? "nil")")
print("🔵 [Supabase] Authenticated: \(isAuthenticated)")

do {
    let result = try await ...
    print("✅ [Supabase] Success: \(result)")
} catch {
    print("❌ [Supabase] Error: \(error)")
    print("❌ [Supabase] Details: \(error.localizedDescription)")
}
```

---

## Testing Report Template

Use this to document your testing:

```
SUPABASE INTEGRATION TEST REPORT
================================

Date: _____________
Tester: __________
Device: __________
iOS Version: _____

BASIC TESTS
[ ] Open settings view
[ ] Anonymous sign-in
[ ] Sign out

DATABASE TESTS
[ ] Load empty favorites
[ ] Save favorite
[ ] Load saved favorites
[ ] Multiple favorites

EMAIL AUTH (Optional)
[ ] Sign up
[ ] Sign in
[ ] Persist across launches

INTEGRATION TESTS
[ ] Auto sign-in
[ ] Auto-sync
[ ] Cross-device sync

ERROR HANDLING
[ ] No internet
[ ] Invalid credentials
[ ] Graceful failures

SECURITY
[ ] User isolation
[ ] RLS working

NOTES:
_______________________________
_______________________________
_______________________________

OVERALL STATUS: [ ] PASS  [ ] FAIL  [ ] PARTIAL
```

---

## Success Criteria

Your integration is **production ready** if:

✅ All Level 1 tests pass (Basic Connection)
✅ All Level 2 tests pass (Database)
✅ All Level 5 tests pass (Error Handling)
✅ All Level 7 tests pass (Security)

Optional but recommended:
- Level 3 (Email Auth) if you need it
- Level 4 (Auto-sync) for better UX
- Level 8 (API Logging) for analytics

---

## Next Steps After Testing

Once all tests pass:

1. **Document** - Note any issues or edge cases
2. **Deploy** - Use in production with confidence
3. **Monitor** - Check Supabase dashboard for usage
4. **Iterate** - Add advanced features from examples
5. **Scale** - Supabase grows with your user base

---

Happy testing! 🧪✨
