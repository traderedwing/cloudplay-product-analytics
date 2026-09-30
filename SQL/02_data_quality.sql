-- ============================================================
-- 02. data quality checks
-- CloudPlay Product Analytics
-- ============================================================

-- This script validates the synthetic dataset after loading it
-- into PostgreSQL and before performing analytical queries.


-- ============================================================
-- 1. table row counts
-- ============================================================

select 'users' as table_name, count(*) as row_count
from users

union all

select 'subscriptions', count(*)
from subscriptions

union all

select 'payments', count(*)
from payments

union all

select 'gaming_sessions', count(*)
from gaming_sessions

union all

select 'events', count(*)
from events

union all

select 'product_events', count(*)
from product_events;


-- Expected final database size:
--
-- users            :    150,000
-- subscriptions    :    250,000
-- payments         :  2,622,107
-- gaming_sessions  :  4,000,000
-- events           : 12,000,000
-- product_events   : 16,756,199
--
-- total            : 35,778,306 rows


-- ============================================================
-- 2. primary key uniqueness
-- ============================================================

select
    count(*) as total_rows,
    count(distinct user_id) as unique_ids
from users;

select
    count(*) as total_rows,
    count(distinct subscription_id) as unique_ids
from subscriptions;

select
    count(*) as total_rows,
    count(distinct payment_id) as unique_ids
from payments;

select
    count(*) as total_rows,
    count(distinct session_id) as unique_ids
from gaming_sessions;

select
    count(*) as total_rows,
    count(distinct event_id) as unique_ids
from events;

select
    count(*) as total_rows,
    count(distinct event_id) as unique_ids
from product_events;


-- ============================================================
-- 3. missing critical identifiers
-- ============================================================

select
    count(*) as null_user_ids
from users
where user_id is null;

select
    count(*) as null_subscription_ids
from subscriptions
where subscription_id is null;

select
    count(*) as null_payment_ids
from payments
where payment_id is null;

select
    count(*) as null_session_ids
from gaming_sessions
where session_id is null;

select
    count(*) as null_event_ids
from events
where event_id is null;

select
    count(*) as null_product_event_ids
from product_events
where event_id is null;


-- ============================================================
-- 4. orphan user references
-- ============================================================

select
    count(*) as orphan_subscriptions
from subscriptions s
left join users u
    on s.user_id = u.user_id
where u.user_id is null;

select
    count(*) as orphan_payments
from payments p
left join users u
    on p.user_id = u.user_id
where u.user_id is null;

select
    count(*) as orphan_sessions
from gaming_sessions gs
left join users u
    on gs.user_id = u.user_id
where u.user_id is null;

select
    count(*) as orphan_product_events
from product_events pe
left join users u
    on pe.user_id = u.user_id
where u.user_id is null;


-- ============================================================
-- 5. date and timestamp validation
-- ============================================================

-- Subscription end date should not precede its start date.

select
    count(*) as invalid_subscription_dates
from subscriptions
where subscription_end_date < subscription_start_date;


-- Gaming session end should not precede session start.

select
    count(*) as invalid_session_dates
from gaming_sessions
where session_end < session_start;


-- ============================================================
-- 6. payment validation
-- ============================================================

select
    min(amount) as min_amount,
    max(amount) as max_amount,
    avg(amount) as avg_amount
from payments;


select
    payment_status,
    count(*) as payments
from payments
group by payment_status
order by payments desc;


-- Check for negative payment amounts.

select
    count(*) as negative_payment_amounts
from payments
where amount < 0;


-- ============================================================
-- 7. gaming session metric validation
-- ============================================================

select
    min(queue_time_seconds) as min_queue,
    max(queue_time_seconds) as max_queue,
    min(avg_latency_ms) as min_latency,
    max(avg_latency_ms) as max_latency,
    min(avg_fps) as min_fps,
    max(avg_fps) as max_fps
from gaming_sessions;


-- ============================================================
-- 8. product event validation
-- ============================================================

select
    event_type,
    count(*) as event_count
from product_events
group by event_type
order by event_count desc;


select
    count(distinct journey_id) as unique_journeys
from product_events;


-- ============================================================
-- data quality notes
-- ============================================================

-- The checks above validate:
--
-- 1. expected table volumes after data loading;
-- 2. uniqueness of primary identifiers;
-- 3. missing critical IDs;
-- 4. referential integrity between users and fact tables;
-- 5. logical date and timestamp ordering;
-- 6. payment value distributions;
-- 7. technical gaming-session metric ranges;
-- 8. product-event and journey coverage.
--
-- Because the dataset is synthetic, unusually uniform variables
-- are preserved when they reflect the generation process rather
-- than data corruption.