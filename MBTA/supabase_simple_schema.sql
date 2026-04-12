-- Analytics Schema for MBTA App
-- Backend monitoring only - users never see this
-- Run in Supabase SQL Editor: https://ifooqfgcpeczamayyzja.supabase.co

-- Track MBTA API usage for rate limiting & monitoring
create table if not exists api_logs (
  id bigserial primary key,
  endpoint text not null,
  status_code integer,
  response_time_ms integer,
  route_name text,
  direction_name text,
  stop_name text,
  timestamp timestamp with time zone default now() not null
);

create index idx_api_logs_timestamp on api_logs(timestamp desc);
create index idx_api_logs_endpoint on api_logs(endpoint);
create index idx_api_logs_route on api_logs(route_name);

-- View for requests per minute
create or replace view api_requests_per_minute as
select 
  date_trunc('minute', timestamp) as minute,
  endpoint,
  count(*) as request_count,
  avg(response_time_ms) as avg_response_time,
  count(*) filter (where status_code between 200 and 299) as successful,
  count(*) filter (where status_code >= 400) as errors
from api_logs
group by date_trunc('minute', timestamp), endpoint
order by minute desc;

-- View for popular routes
create or replace view popular_routes as
select 
  route_name,
  direction_name,
  stop_name,
  count(*) as request_count
from api_logs
where route_name is not null
group by route_name, direction_name, stop_name
order by request_count desc;

-- Done!

