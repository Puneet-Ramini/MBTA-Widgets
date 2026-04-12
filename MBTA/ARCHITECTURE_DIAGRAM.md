# 🏗️ Supabase Integration Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Your MBTA App                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────────┐         ┌──────────────────┐          │
│  │  ContentView   │────────▶│ SupabaseSettings │          │
│  │  (Main UI)     │   ☁️    │     View         │          │
│  └───────┬────────┘         └────────┬─────────┘          │
│          │                            │                     │
│          │                            │                     │
│  ┌───────▼───────────────┐   ┌───────▼─────────────┐      │
│  │  ArrivalsViewModel    │   │  SupabaseService    │      │
│  │  ────────────────     │   │  ───────────────     │      │
│  │  • Load routes        │   │  • Authentication   │      │
│  │  • Save favorites     │   │  • Database ops     │      │
│  │  • API calls          │   │  • Cloud sync       │      │
│  └───────┬───────────────┘   └────────┬────────────┘      │
│          │                             │                    │
│          │    ┌────────────────────────┘                    │
│          │    │                                             │
├──────────┼────┼─────────────────────────────────────────────┤
│          │    │                                             │
│  ┌───────▼────▼──────┐      ┌──────────────────────┐      │
│  │  MBTAService      │      │  SupabaseConfig      │      │
│  │  ──────────────   │      │  ──────────────      │      │
│  │  • MBTA API       │      │  • Project URL       │      │
│  │  • Predictions    │      │  • Publishable Key   │      │
│  └───────────────────┘      └──────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ HTTPS
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Supabase Backend                         │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────┐               │
│  │   Auth System    │  │    Database      │               │
│  │   ────────────   │  │    ────────       │               │
│  │   • Anonymous    │  │    • favorites   │               │
│  │   • Email/Pass   │  │    • api_logs    │               │
│  │   • JWT Tokens   │  │    • preferences │               │
│  └──────────────────┘  └──────────────────┘               │
│                                                             │
│  ┌──────────────────────────────────────────┐              │
│  │      Row Level Security (RLS)            │              │
│  │      ──────────────────────               │              │
│  │      • User isolation                    │              │
│  │      • Automatic policy enforcement      │              │
│  └──────────────────────────────────────────┘              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagrams

### 1. Save Favorite to Cloud

```
┌──────────┐
│   User   │ Taps "Save to Favorite 1"
└────┬─────┘
     │
     ▼
┌─────────────────────┐
│ ArrivalsViewModel   │ Creates SavedFavorite object
└──────┬──────────────┘
       │
       ├──────────────────────────────────────┐
       │                                      │
       ▼                                      ▼
┌──────────────┐                    ┌─────────────────┐
│ Local Storage│ Save to UserDefaults│ SupabaseService │
│ (Immediate)  │                    │ (Async)         │
└──────────────┘                    └────────┬────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │ Supabase API    │
                                    │ POST /favorites │
                                    └────────┬────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │ Database Table  │
                                    │ Row inserted    │
                                    └─────────────────┘
```

### 2. Load Favorites from Cloud

```
┌──────────┐
│   User   │ Opens app / taps "Load from Cloud"
└────┬─────┘
     │
     ▼
┌─────────────────────┐
│ SupabaseService     │ Check if authenticated
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Supabase API        │ GET /favorites?user_id=...
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Database Query      │ SELECT * FROM favorites WHERE user_id = auth.uid()
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Row Level Security  │ Automatically filters by authenticated user
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Return JSON Data    │ [{"route_id": "39", "route_name": "39", ...}]
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Decode to Models    │ Array<SavedFavorite>
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Update UI           │ Display in settings or merge with local
└─────────────────────┘
```

### 3. Authentication Flow

```
┌──────────┐
│   User   │ Taps "Sign In Anonymously"
└────┬─────┘
     │
     ▼
┌─────────────────────┐
│ SupabaseService     │ Call signInAnonymously()
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Supabase Auth API   │ POST /auth/v1/signup (anonymous)
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Create User Record  │ Generate UUID, create auth.users entry
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Generate JWT Token  │ Sign JWT with user_id and metadata
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Return Session      │ {user: {...}, access_token: "...", refresh_token: "..."}
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Store in Service    │ currentUser = user, isAuthenticated = true
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Update UI           │ Show "Connected" status
└─────────────────────┘
```

---

## Security Architecture

### Row Level Security (RLS)

```
┌─────────────────────────────────────────────────────────┐
│                    Database Layer                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  User 1 requests:                                       │
│  SELECT * FROM favorites                                │
│                                                         │
│         │                                               │
│         ▼                                               │
│  ┌────────────────────────────────┐                    │
│  │  RLS Policy Check:             │                    │
│  │  WHERE user_id = auth.uid()    │                    │
│  └───────────┬────────────────────┘                    │
│              │                                          │
│              ▼                                          │
│  ┌────────────────────────────────┐                    │
│  │  Returns only User 1's data:   │                    │
│  │  • Favorite A                  │                    │
│  │  • Favorite B                  │                    │
│  └────────────────────────────────┘                    │
│                                                         │
│  User 2 makes same request:                            │
│  SELECT * FROM favorites                                │
│                                                         │
│         │                                               │
│         ▼                                               │
│  ┌────────────────────────────────┐                    │
│  │  RLS Policy Check:             │                    │
│  │  WHERE user_id = auth.uid()    │                    │
│  └───────────┬────────────────────┘                    │
│              │                                          │
│              ▼                                          │
│  ┌────────────────────────────────┐                    │
│  │  Returns only User 2's data:   │                    │
│  │  • Favorite X                  │                    │
│  │  • Favorite Y                  │                    │
│  └────────────────────────────────┘                    │
│                                                         │
│  ✅ Users NEVER see each other's data                  │
│  ✅ Enforced at database level                         │
│  ✅ Cannot be bypassed from client                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Component Relationships

### File Dependencies

```
MBTAApp.swift
    └─▶ ContentView.swift
            ├─▶ ArrivalsViewModel
            │       ├─▶ MBTAService
            │       └─▶ SupabaseService (optional sync)
            │
            └─▶ SupabaseSettingsView
                    └─▶ SupabaseService
                            └─▶ SupabaseConfig

SupabaseService.swift
    ├─▶ Uses: Supabase (package)
    ├─▶ Uses: SupabaseConfig
    └─▶ Used by: ArrivalsViewModel, SupabaseSettingsView

MBTAWidget.swift
    └─▶ Uses: WidgetMBTAService (separate from app)
```

### Package Dependencies

```
MBTA App
    └─▶ Supabase Swift (2.0+)
            ├─▶ Supabase Auth
            ├─▶ Supabase Database
            ├─▶ Supabase Realtime
            └─▶ PostgREST
```

---

## Database Schema

### Entity Relationship

```
┌─────────────────┐
│   auth.users    │ (Built-in Supabase table)
│   ───────────   │
│   • id (UUID)   │
│   • email       │
│   • created_at  │
└────────┬────────┘
         │
         │ One-to-Many
         │
    ┌────┴──────┬──────────┬─────────────┐
    │           │          │             │
    ▼           ▼          ▼             ▼
┌───────┐  ┌────────┐ ┌──────────┐ ┌──────────────┐
│favorites│ │api_logs│ │user_prefs│ │shared_favorites│
│─────────│ │────────│ │──────────│ │───────────────│
│• user_id│ │• user_id│ │• user_id │ │• created_by   │
│• route  │ │• endpoint│ │• theme  │ │• share_code  │
│• stop   │ │• status │ │• settings│ │• route       │
└─────────┘ └─────────┘ └──────────┘ └──────────────┘
```

### Data Types

```
favorites
├── id: bigserial (auto-increment)
├── user_id: uuid (references auth.users)
├── mode: text ("Bus", "Subway", "Commuter Rail")
├── route_id: text ("39", "Red", "CR-Worcester")
├── route_name: text (display name)
├── direction_id: integer (0 or 1)
├── direction_name: text ("Outbound", "Inbound")
├── direction_destination: text ("Back Bay Station")
├── stop_id: text ("64")
├── stop_name: text ("Huntington Ave @ Perkins St")
├── created_at: timestamp with time zone
└── updated_at: timestamp with time zone
```

---

## API Request Flow

### Example: Fetch Favorites

```
1. Swift Code:
   let favorites = try await SupabaseService.shared.fetchFavorites()

2. HTTP Request:
   GET https://ifooqfgcpeczamayyzja.supabase.co/rest/v1/favorites
   Headers:
     apikey: <SUPABASE_PUBLISHABLE_KEY>
     Authorization: Bearer <jwt_token>

3. Database Query (with RLS):
   SELECT * FROM favorites
   WHERE user_id = auth.uid()  -- Automatically added by RLS

4. Response:
   [
     {
       "id": 1,
       "user_id": "123e4567-e89b-12d3-a456-426614174000",
       "mode": "Bus",
       "route_id": "39",
       "route_name": "39",
       ...
     }
   ]

5. Swift Decoding:
   JSON → Array<SavedFavorite>
```

---

## State Management

### SupabaseService Observable State

```
@MainActor
class SupabaseService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool
    
    ┌─────────────────┐
    │  Initial State  │
    │  ─────────────  │
    │  user: nil      │
    │  auth: false    │
    └────────┬────────┘
             │
             │ signInAnonymously()
             ▼
    ┌─────────────────┐
    │  Authenticated  │
    │  ─────────────  │
    │  user: User     │
    │  auth: true     │
    └────────┬────────┘
             │
             │ signOut()
             ▼
    ┌─────────────────┐
    │  Signed Out     │
    │  ─────────────  │
    │  user: nil      │
    │  auth: false    │
    └─────────────────┘
}
```

### SwiftUI Observation

```
SupabaseSettingsView
    @StateObject var supabase = SupabaseService.shared
    
    View updates automatically when:
    • isAuthenticated changes
    • currentUser changes
    
    Triggers:
    • Show/hide sign-in buttons
    • Display user info
    • Enable/disable features
```

---

## Performance Considerations

### Caching Strategy

```
┌──────────────────┐
│   First Launch   │
└────────┬─────────┘
         │
         ├─▶ Load from UserDefaults (instant)
         │   Display immediately
         │
         └─▶ Fetch from Supabase (background)
             Merge/update local data
             Refresh UI
```

### Network Optimization

```
Local Storage (UserDefaults)
├─▶ Instant access
├─▶ No network required
└─▶ Offline support

Cloud Sync (Supabase)
├─▶ Async, non-blocking
├─▶ Graceful error handling
└─▶ Optional enhancement
```

---

## Deployment Checklist

### Development
- [x] Supabase project created
- [x] Package dependency added
- [x] Database schema created
- [x] RLS policies enabled
- [x] Test authentication
- [x] Test data operations

### Production
- [ ] Move API keys to secure storage
- [ ] Enable email confirmation (optional)
- [ ] Set up monitoring
- [ ] Configure rate limits
- [ ] Test on multiple devices
- [ ] Set up backup strategy

---

This architecture provides:
✅ **Security** - RLS protects all data
✅ **Scalability** - Supabase handles growth
✅ **Reliability** - Local + cloud redundancy
✅ **Performance** - Async operations, no blocking
✅ **Maintainability** - Clean separation of concerns
