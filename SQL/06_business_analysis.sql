-- ============================================================
-- 06_business_analysis.sql
-- cloudplay: business and product analysis
-- ============================================================

-- business question:
-- which user segments generate the most value, and how does
-- product usage differ between them?
--
-- the analysis focuses on:
-- 1. monetization by acquisition channel
-- 2. engagement by acquisition channel
-- 3. payer conversion by acquisition channel
-- 4. gaming experience and engagement
-- 5. data-quality limitations found during analysis


-- ============================================================
-- 1. monetization by acquisition channel
-- ============================================================

-- compare paying users, successful payments, total revenue
-- and cumulative revenue per paying user (rppu) by channel.

select
	u.acquisition_channel,
	count(distinct p.user_id) as paying_users,
	count(p.payment_id) as successful_payments,
	sum(p.amount) as revenue,
	round(sum(p.amount) / count(distinct p.user_id), 2) as rppu 
from users u
join payments p on u.user_id = p.user_id
where p.payment_status = 'successful'
group by u.acquisition_channel
order by revenue desc;

/*
findings:

- organic generated the highest total revenue (8.80m)
  and had the highest rppu (262.64).

- rppu differences between acquisition channels were relatively
  small, ranging from 249.63 for tiktok to 262.64 for organic.

- channels therefore differ much more in scale than in cumulative
  revenue generated per paying user.

limitation:

- rppu is calculated across the entire observation period.
  it is not normalized for user tenure, so users acquired earlier
  may have had more time to generate revenue.
*/


-- ============================================================
-- 2. engagement by acquisition channel
-- ============================================================

select 
	u.acquisition_channel,
	count(distinct gs.user_id) as users_with_sessions,
	count(gs.session_id) as total_sessions,
	round(1.0 * count(gs.session_id) / count(distinct gs.user_id), 2) as avg_sessions_per_user
from users u 
join gaming_sessions gs on u.user_id = gs.user_id 
group by u.acquisition_channel
order by avg_sessions_per_user desc;

-- validate the total number of users acquired through each channel

select
	acquisition_channel,
	count(user_id) as total_users
from users 
group by acquisition_channel
order by total_users desc;

/*
finding:

- total users and users with gaming sessions are identical
  for every acquisition channel.

- therefore, all 150,000 users in the synthetic dataset have
  at least one gaming session.

- because user-to-gaming conversion is 100%, this metric does
  not provide useful differentiation between channels.

- average sessions per user is also very similar across channels,
  approximately 26.5-26.8 sessions per user.
*/


-- ============================================================
-- 3. payer conversion by acquisition channel
-- ============================================================

-- reduce payments to one row per paying user before joining.
-- this prevents users with multiple successful payments from
-- being counted multiple times.

with pay as(
	select distinct
		user_id 
	from payments
	where payment_status ='successful'
)
select 
	u.acquisition_channel,
	count(u.user_id) as total_users,
	count(pa.user_id) as paying_users,
	round(100.0 * count(pa.user_id) / count(u.user_id),2) as payer_conversion_rate
from users u 
left join pay pa on u.user_id = pa.user_id 
group by u.acquisition_channel
order by payer_conversion_rate desc;

/*
finding:

- payer conversion is highly consistent across acquisition channels,
  ranging from approximately 79.5% to 80.1%.

- together with similar rppu and engagement levels, this suggests
  that the main difference between acquisition channels in this
  dataset is scale rather than major differences in observed
  per-user monetization or engagement.

- these are descriptive associations and should not be interpreted
  as causal effects of acquisition channel.
*/


-- ============================================================
-- 4. gaming experience data validation
-- ============================================================

-- check whether disconnect_flag contains enough variation
-- for meaningful analysis.

select
    disconnect_flag,
    count(*) as sessions
from gaming_sessions
group by disconnect_flag;

/*
finding:

- all 4,000,000 gaming sessions have disconnect_flag = false.

- because the variable has no variance, it cannot be used to
  investigate the relationship between disconnects and engagement.

- the raw data is preserved and this limitation is documented
  rather than modifying the synthetic dataset.
*/
-- ============================================================
-- 5. latency analysis
-- ============================================================

-- 5.1 session-level latency distribution

select
	min(avg_latency_ms) as min_latency,
	percentile_cont(0.25) within group(order by avg_latency_ms) as p25,
	round(avg(avg_latency_ms), 2) as avg_latency,
	percentile_cont(0.5) within group(order by avg_latency_ms) as median,
	percentile_cont(0.75) within group(order by avg_latency_ms) as p75,
	max(avg_latency_ms) as max_latency
from gaming_sessions gs;

/*
session-level latency:
min = 10 ms
mean = 42.46 ms
median = 40 ms
p25 = 30 ms
p75 = 52 ms
max = 148 ms
*/


-- 5.2 user-level latency distribution

-- experience is aggregated to one row per user before segmentation.

with lat_user as (
	select 
		user_id,
		round(avg(avg_latency_ms), 2) as avg_user_latency,
		count(session_id) as total_sessions
	from gaming_sessions gs 
	group by user_id
)
select
	min(avg_user_latency) as min,
	percentile_cont(0.25) within group(order by avg_user_latency) as p25,
	percentile_cont(0.5) within group(order by avg_user_latency) as median,
	percentile_cont(0.75) within group(order by avg_user_latency) as p75,
	max(avg_user_latency) as max
from lat_user;

/*
user-level latency:
min = 14.67 ms
p25 = 39.13 ms
median = 41.85 ms
p75 = 45.07 ms
max = 86.00 ms
*/


-- 5.3 engagement by user-level latency quartile

with lat_user as (
	select 
		user_id,
		round(avg(avg_latency_ms), 2) as avg_user_latency,
		count(session_id) as total_sessions
	from gaming_sessions gs 
	group by user_id
),
latency_segments as (
	select
		user_id,
		avg_user_latency,
		total_sessions,
		case
			when avg_user_latency <= 39.13 then 'low'
			when avg_user_latency <= 41.85 then 'medium'
			when avg_user_latency <= 45.07 then 'high'
			else 'very high'
		end as latency_segment
	from lat_user
)
select
	latency_segment,
	count(user_id) as users,
	round(avg(total_sessions), 2) as avg_sessions_per_user
from latency_segments
group by latency_segment
order by avg_sessions_per_user desc; 

/*
results:

medium     37,465 users   30.41 sessions/user
high       37,402 users   29.11 sessions/user
very high  37,492 users   23.77 sessions/user
low        37,641 users   23.40 sessions/user

the relationship is not monotonic:
medium and high latency groups show higher session counts than
both extreme groups.
*/


-- 5.4 linear correlation between latency and engagement

with lat_user as (
    select
        user_id,
        round(avg(avg_latency_ms), 2) as avg_user_latency,
        count(session_id) as total_sessions
    from gaming_sessions
    group by user_id
)
select
    corr(
        avg_user_latency,
        total_sessions
    ) as latency_sessions_correlation
from lat_user;

/*
pearson correlation = -0.0030

there is effectively no linear relationship between average
user latency and total sessions in this dataset.

this does not rule out a non-linear relationship and does not
establish causality.
*/


-- ============================================================
-- 6. queue time analysis
-- ============================================================

-- 6.1 session-level queue time distribution

select
	min(queue_time_seconds) as min_queue,
	round(avg(queue_time_seconds), 2) as avg_queue,
	percentile_cont(0.5) within group(order by queue_time_seconds) as median_queue,
	max(queue_time_seconds) as max_queue
from gaming_sessions gs;

/*
session-level queue time:
min = 0 sec
mean = 75.73 sec
median = 70 sec
max = 298 sec
*/

-- 6.2 user-level queue time distribution

with queue_user as(
	select
		user_id,
		round(avg(queue_time_seconds), 2) as avg_user_queue,
		count(session_id) as total_sessions
	from gaming_sessions gs 
	group by user_id
)
select
	min(avg_user_queue) as min,
	percentile_cont(0.25) within group(order by avg_user_queue) as p25,
	percentile_cont(0.5) within group(order by avg_user_queue) as median,
	percentile_cont(0.75) within group(order by avg_user_queue) as p75,
	max(avg_user_queue) as max
from queue_user;

/*
user-level queue time:
min = 0.00 sec
p25 = 67.00 sec
median = 75.08 sec
p75 = 83.92 sec
max = 177.00 sec
*/

-- 6.3 engagement by user-level queue-time quartile

with queue_user as (
    select
        user_id,
        round(avg(queue_time_seconds), 2) as avg_user_queue,
        count(session_id) as total_sessions
    from gaming_sessions
    group by user_id
),
queue_segments as (
	select
		user_id,
		avg_user_queue,
		total_sessions,
		case
			when avg_user_queue <= 67.00 then 'low queue'
			when avg_user_queue <= 75.08 then 'medium queue'
			when avg_user_queue <= 83.92 then 'high queue'
			else 'very high queue'
		end as queue_segment
	from queue_user
)		
select 
	queue_segment,
	count(user_id) as users,
	round(avg(total_sessions), 2) as avg_sessions_per_user
from queue_segments 
group by queue_segment
order by avg_sessions_per_user desc;

/*
results:

medium queue     37,332 users   29.90 sessions/user
high queue       37,483 users   28.82 sessions/user
very high queue  37,495 users   24.09 sessions/user
low queue        37,690 users   23.88 sessions/user

as with latency, the relationship is not monotonic.
*/

-- 6.4 linear correlation between queue time and engagement

with queue_user as (
    select
        user_id,
        round(avg(queue_time_seconds), 2) as avg_user_queue,
        count(session_id) as total_sessions
    from gaming_sessions
    group by user_id
)
select
    corr(avg_user_queue, total_sessions) as queue_sessions_correlation
from queue_user;

/*
pearson correlation = -0.0018

there is effectively no linear relationship between average
user queue time and total sessions in this dataset.
*/


-- ============================================================
-- 7. conclusions and limitations
-- ============================================================

/*
key findings:

1. acquisition channels differ substantially in scale, but observed
   per-user behavior is comparatively similar.

2. organic generates the highest absolute revenue and the highest
   cumulative rppu, while rppu differences across all channels
   remain relatively small.

3. payer conversion is approximately 80% across every acquisition
   channel, and average sessions per user are also very similar.

4. all users in the synthetic dataset have at least one gaming
   session, making user-to-gaming conversion uninformative.

5. disconnect_flag contains no variation: all 4m sessions are
   recorded as non-disconnected.

6. latency and queue-time quartiles show similar non-linear
   engagement patterns, with middle groups having more sessions
   than the extreme groups.

7. pearson correlations between engagement and both experience
   metrics are approximately zero:
       latency vs sessions: -0.0030
       queue time vs sessions: -0.0018

   therefore, the data does not support a meaningful linear
   relationship between either metric and total user sessions.

limitations:

- the dataset is synthetic, so patterns may reflect the assumptions
  and mechanics used during data generation rather than real-world
  user behavior.

- the analysis is observational. associations between variables
  should not be interpreted as causal effects.

- rppu is cumulative and is not normalized for user tenure.

- latency and queue time are aggregated across the same observation
  period used to calculate total sessions. this should be considered
  when interpreting their relationship with engagement.

- quartile boundaries are derived from this dataset and should not
  be interpreted as universal product-performance thresholds.

- several synthetic variables show unusually uniform behavior,
  including 100% of users having gaming sessions and zero recorded
  disconnects.
*/