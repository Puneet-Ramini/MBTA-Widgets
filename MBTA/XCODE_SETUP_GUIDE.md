# 🎯 Xcode Setup Steps (Visual Guide)

## Step 1: Add Supabase Package to Your Project

### In Xcode:

1. **Open Your Project**
   - Make sure your MBTA project is open in Xcode

2. **Go to File Menu**
   ```
   File → Add Package Dependencies...
   ```

3. **Enter Package URL**
   - In the search field at top right, paste:
   ```
   https://github.com/supabase/supabase-swift
   ```
   - Press Enter/Return

4. **Select Version**
   - In "Dependency Rule" dropdown, select: **"Up to Next Major Version"**
   - Version should be: **2.0.0** (or latest)
   - Click: **"Add Package"**

5. **Choose Products**
   - You'll see a list of products
   - Check the box for: **"Supabase"**
   - Make sure it's added to your **MBTA** target
   - Click: **"Add Package"**

6. **Wait for Download**
   - Xcode will download and integrate the package
   - You'll see progress in the toolbar
   - When done, you'll see "Supabase" in your Project Navigator under "Package Dependencies"

### Verify Installation:

Add this to the top of any Swift file:
```swift
import Supabase
```

If it compiles without errors, you're good! ✅

---

## Step 2: Create Database Tables in Supabase

### In Your Browser:

1. **Open Supabase Dashboard**
   - Go to: https://ifooqfgcpeczamayyzja.supabase.co
   - Log in if needed

2. **Open SQL Editor**
   - Look at left sidebar
   - Click: **SQL Editor** (icon looks like `</>`)

3. **Create New Query**
   - Click: **"+ New Query"** button (top left)

4. **Copy SQL Schema**
   - Open the file: `supabase_schema.sql`
   - Copy ALL the SQL code (Cmd+A, Cmd+C)

5. **Paste and Run**
   - Paste into the SQL Editor (Cmd+V)
   - Click: **"RUN"** button (bottom right) or press Cmd+Enter
   
6. **Verify Success**
   - You should see: "Success. No rows returned"
   - Scroll down to see: "api_logs, favorites, shared_favorites, user_preferences"

### Alternative: Create Tables One by One

If you prefer to understand what each table does:

#### Minimal Setup (Just Favorites):

```sql
-- Run this first
create table favorites (
  id bigserial primary key,
  user_id uuid references auth.users,
  mode text not null,
  route_id text not null,
  route_name text not null,
  direction_id integer not null,
  direction_name text not null,
  direction_destination text not null,
  stop_id text not null,
  stop_name text not null,
  created_at timestamp with time zone default now() not null
);

alter table favorites enable row level security;

create policy "Users can manage their favorites"
  on favorites for all
  using (auth.uid() = user_id);
```

Then you can add other tables later!

---

## Step 3: Test Your Integration

### In Xcode:

1. **Build and Run**
   - Press: **Cmd+R** (or click Play button)
   - Wait for app to launch on simulator/device

2. **Open Supabase Settings**
   - Look for **cloud icon (☁️)** in top right corner
   - Tap it

3. **Sign In**
   - Tap: **"Sign In Anonymously"**
   - Wait a few seconds

4. **Verify Connection**
   - You should see:
     - ✅ Status: "Connected" (in green)
     - ✅ User ID displayed
     - ✅ Success message at bottom

### If It Works:
🎉 You're done! Supabase is fully integrated!

### If It Doesn't Work:

**Error: "Cannot find 'Supabase' in scope"**
- ✅ Go back to Step 1
- ✅ Make sure package is added to correct target
- ✅ Try: Product → Clean Build Folder
- ✅ Try: File → Packages → Reset Package Caches

**Error: "Table favorites does not exist"**
- ✅ Go back to Step 2
- ✅ Run the SQL commands again
- ✅ Check you're logged into correct Supabase project

**Error: "Network error" or "Connection failed"**
- ✅ Check your internet connection
- ✅ Verify Supabase project URL in `SupabaseConfig.swift`
- ✅ Try again - might be temporary network issue

---

## Step 4: Enable Features (Optional)

### Auto Sign-In on App Launch

1. Open: `MBTAApp.swift`
2. Replace with:

```swift
import SwiftUI

@main
struct MBTAApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .task {
                    // Auto sign-in when app launches
                    if !SupabaseService.shared.isAuthenticated {
                        try? await SupabaseService.shared.signInAnonymously()
                    }
                }
        }
    }
}
```

### Auto-Sync Favorites to Cloud

1. Open: `ArrivalsViewModel.swift`
2. Find the `saveFavorite(at:)` method
3. Add this at the end (before the closing `}`):

```swift
// Sync to cloud
Task {
    try? await SupabaseService.shared.saveFavorite(favorite)
}
```

### Load Favorites from Cloud on Launch

1. Open: `ArrivalsViewModel.swift`
2. Add this method:

```swift
func syncFromCloud() async {
    guard SupabaseService.shared.isAuthenticated else { return }
    
    do {
        let cloudFavorites = try await SupabaseService.shared.fetchFavorites()
        
        // Update empty slots with cloud data
        if quickFavorites[0] == nil && !cloudFavorites.isEmpty {
            quickFavorites[0] = cloudFavorites[0]
        }
        if quickFavorites[1] == nil && cloudFavorites.count > 1 {
            quickFavorites[1] = cloudFavorites[1]
        }
        
        saveQuickFavorites()
    } catch {
        print("Cloud sync failed: \(error)")
    }
}
```

3. Call it in `init()`:

```swift
init() {
    loadQuickFavorites()
    
    Task {
        await syncFromCloud()
    }
}
```

---

## Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| Can't find Supabase package | File → Add Package Dependencies, use URL from Step 1 |
| Import Supabase doesn't work | Clean build folder, restart Xcode |
| Table doesn't exist | Run SQL from `supabase_schema.sql` |
| Not authenticated | Tap cloud button, sign in anonymously |
| Can't save to database | Check you're signed in first |
| Data not showing | This is normal! RLS protects your data |

---

## Testing Checklist

Once everything is set up, test these features:

- [ ] App builds without errors
- [ ] Cloud button appears in navigation
- [ ] Can open Supabase settings view
- [ ] "Sign In Anonymously" works
- [ ] Status shows "Connected" (green)
- [ ] User ID is displayed
- [ ] Can tap "Load from Cloud" without errors
- [ ] No crash when saving favorites

If all boxes are checked: **You're production ready!** ✅

---

## What's Next?

### Immediate Use:
1. Start using the cloud button to test features
2. Save a favorite in your app
3. Open cloud settings to see it synced

### This Week:
1. Enable auto-sync (copy code from `SupabaseIntegrationExamples.swift`)
2. Test on multiple devices to see sync in action
3. Add email authentication if needed

### Advanced:
1. Build analytics dashboard using `api_logs` table
2. Add share features for favorite routes
3. Implement real-time notifications
4. Create user preferences screen

---

## File Reference

**Core Files (Created for You):**
- `SupabaseConfig.swift` - Your credentials
- `SupabaseService.swift` - Service layer
- `SupabaseSettingsView.swift` - Settings UI
- `supabase_schema.sql` - Database schema

**Documentation:**
- `QUICKSTART_SUPABASE.md` - Quick start (you are here!)
- `SUPABASE_SETUP.md` - Detailed setup guide
- `SupabaseIntegrationExamples.swift` - Code examples
- `SUPABASE_INTEGRATION_SUMMARY.md` - Overview

**Modified:**
- `ContentView.swift` - Added cloud button

---

## Support

**Need help?**
1. Check `SUPABASE_SETUP.md` for detailed troubleshooting
2. Review code examples in `SupabaseIntegrationExamples.swift`
3. Visit Supabase docs: https://supabase.com/docs

**Working?**
🎉 Awesome! Now check out the examples file for cool features to add!

---

Remember: The integration is **already complete**. You just need to:
1. Add the package (2 min)
2. Run the SQL (2 min)  
3. Test it (1 min)

**That's it!** 🚀
