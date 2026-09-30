-- ============================================================
-- CloudPlay: Retention Analysis
-- ============================================================

-- Business question:
-- How many users return to gaming activity after their first
-- active month, and how does retention differ across cohorts?


-- ============================================================
-- 1. Initial approach: subscription retention
-- ============================================================

-- Subscription renewal retention was initially considered as
-- the basis for measuring user retention.
--
-- Before calculating retention, subscription history was
-- inspected to determine whether subscriptions form a
-- sequential renewal chain for each user.
with multiply_sub as (
    select
        s.user_id
    from subscriptions s
    group by s.user_id
    having count(s.subscription_id) > 1
)
select
    s.user_id,
    s.subscription_id,
    s.subscription_start_date,
    s.subscription_end_date,
    s.status
from subscriptions s
join multiply_sub ms
    on s.user_id = ms.user_id
order by s.user_id, s.subscription_start_date;
-- Finding:
-- users can have multiple overlapping subscriptions.
-- some subscriptions can also start on the same date.
--
-- Therefore, subscription records cannot be treated as a
-- simple sequential renewal chain where each new subscription
-- represents a renewal of the previous one.
--
-- Because of this data structure, subscription renewal
-- retention was not used for the final retention metric.
--
-- Retention is instead measured at the user level using
-- gaming activity.


-- ============================================================
-- 2. Final retention definition
-- ============================================================

-- Users are assigned to cohorts based on the month of their
-- first gaming session.
--
-- cohort_month:
-- the calendar month in which the user had their first
-- gaming session.
--
-- A user is considered retained in month N if they have at
-- least one gaming session during that calendar month.
--
-- month 0 = user's first active month
-- month 1 = next calendar month
-- month 3 = three months after the first active month
-- etc.
--
-- Multiple gaming sessions within the same month do not
-- increase retention: each user is counted only once per
-- activity month.


-- ============================================================
-- 3. Cohort retention calculation
-- ============================================================

-- Step 1:
-- assign each user to a cohort using their first gaming
-- session month.
--
-- Step 2:
-- create one unique user/activity-month combination.
--
-- Step 3:
-- calculate the number of calendar months between the user's
-- cohort month and each activity month.
--
-- Step 4:
-- count active users for each cohort and month number.
--
-- Step 5:
-- use activity_users in month 0 as the original cohort size.
--
-- Step 6:
-- calculate retention rate:
--
-- retention_rate = activity_users / cohort_size * 100
--
-- Step 7:
-- pivot key retention checkpoints (M1, M3, M6, M12) into
-- columns to make cohort-to-cohort comparison easier.
with cohort as(
	select
		gs.user_id,
		date_trunc('month', min(gs.session_start))::date as cohort_month
	from gaming_sessions gs
	group by gs.user_id
),
activity as(
	select
		distinct gs.user_id,
		date_trunc('month',gs.session_start)::date as activity_month
	from gaming_sessions gs 
),
user_activity as(
	select 
		c.user_id,
		c.cohort_month,
		av.activity_month,
		(extract(year from av.activity_month) *12 + extract(month from av.activity_month))
		-
		(extract(year from c.cohort_month) *12 + extract(month from c.cohort_month)) as month_number
	from cohort c
	join activity av
		on c.user_id = av.user_id
),
cohort_activity as(
	select
		cohort_month,
		month_number,
		count(distinct user_id) as activity_users
	from user_activity
	group by  cohort_month, month_number
),
retention as(
	select *,  
		max(case 
				when month_number = 0 then activity_users
			end)
		over(partition by cohort_month) as cohort_size
	from cohort_activity
),
retention_rate as(
	select
		*,
		round(100.0*activity_users / cohort_size, 2) as retention_rate
	from retention
)
select
	cohort_month, 
	max(case
			when month_number=1 then retention_rate end) as M1,
	max(case
			when month_number=3 then retention_rate end) as M3,
	max(case
			when month_number=6 then retention_rate end) as M6,
	max(case
			when month_number=12 then retention_rate end) as M12
from retention_rate
group by cohort_month
order by cohort_month;
-- ============================================================
-- 4. Retention insights
-- ============================================================

-- 1. Newer user cohorts show substantially higher retention
--    compared with cohorts that started using the product
--    in early 2024.
--
-- 2. M1 retention was approximately 56-60% for many early
--    2024 cohorts and increased substantially over time.
--
--    Examples:
--    2024-03: 56.03%
--    2024-06: 59.07%
--    2024-12: 66.66%
--    2025-06: 74.18%
--    2025-12: 88.94%
--    2026-01: 88.72%
--    2026-06: 99.36%
--
-- 3. The improvement is visible across multiple retention
--    checkpoints (M1, M3, M6 and M12), rather than being
--    isolated to a single retention month.
--
-- 4. Within individual cohorts, retention after the initial
--    month is relatively stable rather than showing continuous
--    month-over-month decline.
--
--    For example, the 2025-06 cohort shows:
--    M1  = 74.18%
--    M3  = 73.25%
--    M6  = 75.71%
--    M12 = 74.67%
--
-- 5. The analysis therefore indicates a strong improvement
--    in activity retention for newer cohorts.
--
-- 6. This analysis identifies the retention trend but does
--    not establish why retention improved. Further analysis
--    would be required to investigate potential drivers.


-- ============================================================
-- 5. Analysis limitations
-- ============================================================

-- Activity-based retention:
-- retention in this analysis represents gaming activity,
-- not subscription renewal or payment retention.
--
-- A retained user is a user with at least one gaming session
-- during the given calendar month.


-- Non-continuous retention:
-- this metric does not require users to be active in every
-- previous month.
--
-- For example, a user can be inactive in month 1 and return
-- in month 2. That user will not count toward M1 retention
-- but will count toward M2 retention.


-- Observation window:
-- the dataset ends in August 2026.
--
-- Recent cohorts have therefore not had enough time to reach
-- longer-term retention checkpoints.
--
-- NULL values in M3, M6 or M12 for recent cohorts represent
-- incomplete observation windows, not zero retention.


-- Interpretation:
-- the analysis shows an association between newer cohorts
-- and higher retention.
--
-- It does not establish causality. Additional analysis would
-- be required to determine whether the improvement is related
-- to product changes, acquisition mix, user characteristics
-- or other factors.


-- Dataset:
-- this project uses synthetic data designed to simulate a
-- cloud gaming subscription product. Findings should therefore
-- be interpreted as analytical patterns within the simulated
-- dataset rather than real-world business results.