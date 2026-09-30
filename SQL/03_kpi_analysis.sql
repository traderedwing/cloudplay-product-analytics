-- ============================================================
-- CloudPlay: KPI Analysis
-- ============================================================


-- ============================================================
-- 1. Monthly Subscriber & Revenue KPIs
-- ============================================================

-- Initial approach
-- New subscribers were counted by subscription_start_date.
-- Problem: users who subscribed again were counted as new
-- subscribers more than once.

/*
with new_subscriber as (
    select 
        date_trunc('month', s.subscription_start_date) as mth_s,
        count(distinct s.user_id) as new_subscribers
    from subscriptions s
    group by mth_s
),
paymentss as (
    select
        date_trunc('month', p.payment_date) as mth_p,
        count(distinct p.user_id) as paying_users,
        count(p.payment_id) as successful_payments,
        sum(p.amount) as revenue
    from payments p
    where p.payment_status = 'successful'
    group by mth_p
)
select
    ns.mth_s as mth,
    ns.new_subscribers,
    ps.paying_users,
    ps.successful_payments,
    ps.revenue
from new_subscriber ns
join paymentss ps
    on ns.mth_s = ps.mth_p;
*/


-- Final approach
-- New subscriber = user's first-ever subscription.
-- MIN(subscription_start_date) identifies the first subscription.
with first_subscription as (
    select
        min(s.subscription_start_date) as first_month,
        user_id
    from subscriptions s
    group by user_id
)
,new_subscriber as (
    select 
        date_trunc('month', f_s.first_month) as mth_s,
        count(distinct f_s.user_id) as new_subscribers
    from first_subscription f_s
    group by mth_s
),
paymentss as (
    select
        date_trunc('month', p.payment_date) as mth_p,
        count(distinct p.user_id) as paying_users,
        count(p.payment_id) as successful_payments,
        sum(p.amount) as revenue
    from payments p
    where p.payment_status = 'successful'
    group by mth_p
)
select
    ns.mth_s as mth,
    ns.new_subscribers,
    ps.paying_users,
    ps.successful_payments,
    ps.revenue
from new_subscriber ns
join paymentss ps
    on ns.mth_s = ps.mth_p;


-- ============================================================
-- 2. Investigation: August 2026 Subscriber Spike
-- ============================================================

-- Monthly KPI analysis showed an unusual increase:
-- August 2026 = 8,016 new subscribers,
-- compared with approximately 3,500–3,900 in previous months.


-- 2.1 New subscribers by acquisition channel
-- Goal: determine whether the spike was driven by one
-- acquisition channel or appeared across multiple channels.

with first_subscriptions as (
    select
        user_id,
        min(s.subscription_start_date) as first_subscription_date
    from subscriptions s
    group by s.user_id
)
select
    date_trunc('month', fs.first_subscription_date) as mth,
    u.acquisition_channel,
    count(fs.user_id) as new_subscribers
from first_subscriptions fs
join users u
    on fs.user_id = u.user_id
where fs.first_subscription_date >= '2026-01-01'
  and fs.first_subscription_date < '2026-09-01'
group by mth, u.acquisition_channel
order by mth, u.acquisition_channel;


-- Finding:
-- The increase appeared across all acquisition channels.
-- Therefore, no single channel explains the August spike.


-- 2.2 Daily breakdown of August 2026
-- Goal: check whether the increase was distributed across
-- the month or concentrated on a specific date.

with first_subscriptions as (
    select
        user_id,
        min(s.subscription_start_date) as first_subscription_date
    from subscriptions s
    group by s.user_id
)
select
    fs.first_subscription_date as day,
    count(fs.user_id) as new_subscribers
from first_subscriptions fs
where fs.first_subscription_date >= '2026-08-01'
  and fs.first_subscription_date < '2026-09-01'
group by fs.first_subscription_date
order by fs.first_subscription_date;


-- Finding:
-- From August 1–30, daily new subscribers were approximately
-- 106–156.
-- On August 31, there were 4,320 new subscribers.


-- ============================================================
-- Conclusion
-- ============================================================

-- August 2026 showed 8,016 new subscribers, compared with
-- approximately 3,500-3,900 in previous months.
--
-- The increase was not driven by a specific acquisition channel.
-- Daily analysis identified 4,320 first-time subscriptions on
-- August 31 alone, while August 1-30 remained within the normal
-- daily range.
--
-- August 31 is the final observation date in the dataset,
-- indicating a potential boundary-related data anomaly.
-- Excluding this date, August had 3,696 new subscribers,
-- consistent with previous months.
--
-- The raw data was preserved and the anomaly was documented
-- rather than removed.