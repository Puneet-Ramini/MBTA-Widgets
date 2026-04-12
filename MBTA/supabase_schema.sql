-- Supabase Database Schema for MBTA App
-- Run these commands in your Supabase SQL Editor
-- Dashboard: https://ifooqfgcpeczamayyzja.supabase.co

-- ============================================
-- 1. FAVORITES TABLE
-- ============================================

create table if not exists favorites (
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

-- RLS Policies for favorites
create policy "Users can view their own favorites"
  on favorites for select
  using (auth.uid() = user_id);

create policy "Users can insert their own favorites"
  on favorites for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own favorites"
  on favorites for update
  using (auth.uid() = user_id);

create policy "Users can delete their own favorites"
  on favorites for delete
  using (auth.uid() = user_id);

-- Indexes for better performance
create index if not exists favorites_user_id_idx on favorites(user_id);
create index if not exists favorites_route_id_idx on favorites(route_id);
create index if not exists favorites_created_at_idx on favorites(created_at desc);

-- ============================================
-- 2. API LOGS TABLE (for analytics)
-- ============================================

create table if not exists api_logs (
  id bigserial primary key,
  user_id uuid references auth.users,
  endpoint text not null,
  source text not null,
  status_code integer,
  timestamp timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security
alter table api_logs enable row level security;

-- RLS Policies for api_logs
create policy "Users can insert their own logs"
  on api_logs for insert
  with check (auth.uid() = user_id);

create policy "Users can view their own logs"
  on api_logs for select
  using (auth.uid() = user_id);

-- Indexes for analytics queries
create index if not exists api_logs_user_id_idx on api_logs(user_id);
create index if not exists api_logs_timestamp_idx on api_logs(timestamp desc);
create index if not exists api_logs_endpoint_idx on api_logs(endpoint);
create index if not exists api_logs_source_idx on api_logs(source);

-- ============================================
-- 3. OPTIONAL: USER PREFERENCES TABLE
-- ============================================

create table if not exists user_preferences (
  user_id uuid references auth.users primary key,
  preferred_mode text,
  theme text default 'light',
  notifications_enabled boolean default true,
  widget_refresh_interval integer default 60, -- seconds
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security
alter table user_preferences enable row level security;

-- RLS Policies
create policy "Users can view their own preferences"
  on user_preferences for select
  using (auth.uid() = user_id);

create policy "Users can update their own preferences"
  on user_preferences for all
  using (auth.uid() = user_id);

-- ============================================
-- 4. OPTIONAL: SHARED FAVORITES TABLE
-- ============================================

create table if not exists shared_favorites (
  id uuid primary key default gen_random_uuid(),
  share_code text unique not null,
  created_by uuid references auth.users,
  mode text not null,
  route_id text not null,
  route_name text not null,
  direction_id integer not null,
  direction_name text not null,
  direction_destination text not null,
  stop_id text not null,
  stop_name text not null,
  views integer default 0,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  expires_at timestamp with time zone default (now() + interval '30 days')
);

-- Enable Row Level Security
alter table shared_favorites enable row level security;

-- RLS Policies for shared_favorites
create policy "Anyone can view active shared favorites"
  on shared_favorites for select
  using (expires_at > now());

create policy "Authenticated users can create shared favorites"
  on shared_favorites for insert
  with check (auth.uid() = created_by);

create policy "Creators can delete their shared favorites"
  on shared_favorites for delete
  using (auth.uid() = created_by);

-- Index for fast lookups by share code
create index if not exists shared_favorites_share_code_idx on shared_favorites(share_code);
create index if not exists shared_favorites_created_by_idx on shared_favorites(created_by);

-- ============================================
-- 5. HELPER FUNCTIONS
-- ============================================

-- Function to increment view count on shared favorites
create or replace function increment_share_views(share_code_input text)
returns void
language plpgsql
security definer
as $$
begin
  update shared_favorites
  set views = views + 1
  where share_code = share_code_input;
end;
$$;

-- Function to clean up expired shares (run periodically)
create or replace function cleanup_expired_shares()
returns void
language plpgsql
security definer
as $$
begin
  delete from shared_favorites
  where expires_at < now();
end;
$$;

-- ============================================
-- 6. ANALYTICS VIEWS (Optional)
-- ============================================

-- View for API usage summary
create or replace view api_usage_summary as
select
  endpoint,
  source,
  count(*) as total_requests,
  count(*) filter (where status_code between 200 and 299) as successful_requests,
  count(*) filter (where status_code is null or status_code not between 200 and 299) as failed_requests,
  date_trunc('hour', timestamp) as hour
from api_logs
group by endpoint, source, date_trunc('hour', timestamp)
order by hour desc;

-- View for popular routes
create or replace view popular_routes as
select
  route_id,
  route_name,
  mode,
  count(*) as save_count,
  count(distinct user_id) as unique_users
from favorites
group by route_id, route_name, mode
order by save_count desc;

-- ============================================
-- DONE! 🎉
-- ============================================

-- Verify tables were created:
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('favorites', 'api_logs', 'user_preferences', 'shared_favorites')
order by table_name;

-- Expected output:
-- api_logs
-- favorites
-- shared_favorites
-- user_preferences
