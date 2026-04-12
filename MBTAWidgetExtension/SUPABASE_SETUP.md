# Supabase Integration Guide

## Installation Steps

### Option 1: Swift Package Manager (Recommended)

1. **In Xcode:**
   - Go to `File` → `Add Package Dependencies...`
   - Enter the Supabase Swift package URL:
     ```
     https://github.com/supabase/supabase-swift
     ```
   - Select version: `2.0.0` or later (use "Up to Next Major Version")
   - Click "Add Package"
   - Select these products to add to your target:
     - `Supabase` (main target)
     - `Supabase` (widget extension if you want to use it there)

2. **For the Widget Extension:**
   - If you want to use Supabase in your widget, make sure to add the `Supabase` product to your widget target as well
   - Note: Be mindful of binary size for widgets

### Option 2: Package.swift (if you're using SPM directly)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Supabase", package: "supabase-swift")
        ]
    )
]
```

## Database Schema Setup

You'll need to create these tables in your Supabase dashboard:

### 1. Favorites Table

```sql
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
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security
alter table favorites enable row level security;

-- Allow users to read their own favorites
create policy "Users can view their own favorites"
  on favorites for select
  using (auth.uid() = user_id);

-- Allow users to insert their own favorites
create policy "Users can insert their own favorites"
  on favorites for insert
  with check (auth.uid() = user_id);

-- Allow users to delete their own favorites
create policy "Users can delete their own favorites"
  on favorites for delete
  using (auth.uid() = user_id);

-- Create index for faster queries
create index favorites_user_id_idx on favorites(user_id);
```

### 2. API Logs Table (Optional - for analytics)

```sql
create table api_logs (
  id bigserial primary key,
  user_id uuid references auth.users,
  endpoint text not null,
  source text not null,
  status_code integer,
  timestamp timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security
alter table api_logs enable row level security;

-- Allow authenticated users to insert logs
create policy "Users can insert their own logs"
  on api_logs for insert
  with check (auth.uid() = user_id);

-- Create index for analytics queries
create index api_logs_user_id_idx on api_logs(user_id);
create index api_logs_timestamp_idx on api_logs(timestamp);
```

## Usage Examples

### Initialize in Your App

The service is already configured as a singleton. You can access it anywhere:

```swift
let supabase = SupabaseService.shared
```

### Sign In Anonymously (Easiest Start)

```swift
Task {
    try await SupabaseService.shared.signInAnonymously()
}
```

### Save a Favorite

```swift
Task {
    let favorite = SavedFavorite(
        mode: .bus,
        routeID: "39",
        routeName: "39",
        directionID: 0,
        directionName: "Outbound",
        directionDestination: "Back Bay Station",
        stopID: "64",
        stopName: "Huntington Ave @ Perkins St"
    )
    
    try await SupabaseService.shared.saveFavorite(favorite)
}
```

### Fetch Favorites

```swift
Task {
    let favorites = try await SupabaseService.shared.fetchFavorites()
    print("Loaded \(favorites.count) favorites")
}
```

### Log API Usage

```swift
Task {
    try await SupabaseService.shared.logAPIUsage(
        endpoint: "predictions",
        source: "app",
        statusCode: 200
    )
}
```

## Integration with Existing Code

### Option 1: Sync Local Favorites to Cloud

You can modify `ArrivalsViewModel` to sync favorites both locally and to Supabase:

```swift
func saveFavorite(at index: Int) {
    guard let route = selectedRoute,
          let directionID = selectedDirectionID,
          let stopID = selectedStopID,
          let stopName = selectedStop?.name else {
        return
    }
    
    let favorite = SavedFavorite(
        mode: selectedMode,
        routeID: route.id,
        routeName: route.shortName ?? route.id,
        directionID: directionID,
        directionName: route.directionName(for: directionID),
        directionDestination: route.directionDestination(for: directionID),
        stopID: stopID,
        stopName: stopName
    )
    
    // Save locally
    quickFavorites[index] = favorite
    saveQuickFavorites()
    
    // Sync to Supabase
    Task {
        try? await SupabaseService.shared.saveFavorite(favorite)
    }
}
```

### Option 2: Load Favorites from Cloud on App Launch

In your `ArrivalsViewModel`:

```swift
func loadFavoritesFromCloud() async {
    do {
        let cloudFavorites = try await SupabaseService.shared.fetchFavorites()
        // Merge or replace local favorites
        // This is just an example - you'd want proper sync logic
        if !cloudFavorites.isEmpty {
            self.quickFavorites = [
                cloudFavorites.first,
                cloudFavorites.count > 1 ? cloudFavorites[1] : nil
            ]
            saveQuickFavorites()
        }
    } catch {
        print("Failed to load cloud favorites: \(error)")
    }
}
```

## Security Best Practices

1. **Never commit API keys to Git** - Consider using Xcode configuration files or environment variables for production
2. **Use Row Level Security (RLS)** - Already set up in the SQL above
3. **Enable email confirmation** - In Supabase dashboard under Authentication settings
4. **Rate limit API calls** - Supabase has built-in rate limiting

## Next Steps

1. ✅ Add Supabase package dependency in Xcode
2. ✅ Run the SQL commands in your Supabase dashboard to create tables
3. ✅ Test authentication with `signInAnonymously()`
4. ✅ Test saving and loading favorites
5. Optional: Add user registration/login UI
6. Optional: Implement real-time sync for favorites
7. Optional: Add analytics dashboard using the api_logs table

## Additional Features You Can Build

- **Cross-device sync** - Favorites automatically sync between iPhone and iPad
- **Usage analytics** - Track which routes are most popular
- **Shared favorites** - Allow users to share their favorite routes
- **Historical data** - Store arrival predictions for later analysis
- **User preferences** - Store widget customization, theme preferences, etc.
- **Notifications** - Set up alerts for specific routes/times using Supabase Edge Functions

## Troubleshooting

### "Cannot find 'Supabase' in scope"
- Make sure you've added the package and imported `import Supabase` at the top of files that use it

### "Authentication required"
- Call `signInAnonymously()` or implement email authentication before making database calls

### Row Level Security blocks my queries
- Make sure you're authenticated
- Check your RLS policies in the Supabase dashboard
- For testing, you can temporarily disable RLS (not recommended for production)

## Documentation Links

- [Supabase Swift Docs](https://supabase.com/docs/reference/swift)
- [Supabase Auth Guide](https://supabase.com/docs/guides/auth)
- [Supabase Database Guide](https://supabase.com/docs/guides/database)
