-- ============================================================
-- 05. funnel and user journey analysis
-- ============================================================

-- business question:
-- where do users drop off in the journey from entering the
-- product to starting a gaming session?
--
-- the initial hypothesis was to analyse a sequential funnel:
-- app_open -> login -> game_search -> game_view -> gaming_session.
--
-- before calculating funnel conversion, the event structure was
-- validated to determine whether these events represent mandatory
-- sequential steps in the user journey.


-- ============================================================
-- 1. event structure exploration
-- ============================================================

-- check the distribution of product events

select
    event_type,
    count(event_id) as event_count
from product_events
group by event_type
order by event_count desc;


-- inspect event sequences for sample journeys

select
    journey_id,
    event_timestamp,
    event_type
from product_events
where journey_id between 1 and 10
order by journey_id, event_timestamp;


-- findings:
-- event sequences are not strictly linear.
-- login and game_search are optional steps, and some journeys
-- contain events in a different order than initially expected.
--
-- therefore, app_open -> login -> game_search -> game_view
-- cannot be treated as a mandatory sequential funnel.


-- ============================================================
-- 2. overall journey conversion
-- ============================================================

-- a journey is considered successful if at least one event
-- is linked to a gaming session through gaming_session_id.

with journey_status as (
    select
        journey_id,
        max(
            case
                when gaming_session_id is not null then 1
                else 0
            end
        ) as success
    from product_events
    group by journey_id
)
select
    count(*) as total_journeys,
    sum(success) as successful_journeys,
    count(*) - sum(success) as abandoned_journeys,
    round(100.0 * sum(success) / count(*), 2) as conversion_rate
from journey_status;


-- findings:
-- 5.2 million user journeys were observed in total.
-- 4.0 million journeys resulted in a gaming session,
-- giving an overall journey-to-session conversion rate of 76.92%.
--
-- 1.2 million journeys (23.08%) were abandoned before
-- a gaming session was started.


-- ============================================================
-- 3. abandoned journey analysis
-- ============================================================

-- identify the last recorded event for each abandoned journey

with abandoned as (
    select
        journey_id,
        event_type,
        event_timestamp,
        row_number() over (
            partition by journey_id
            order by event_timestamp desc
        ) as rn
    from product_events
    where gaming_session_id is null
)
select
    event_type,
    count(journey_id) as abandoned_journeys
from abandoned
where rn = 1
group by event_type
order by abandoned_journeys desc;


-- findings:
-- abandoned journeys by last recorded event:
--
-- game_view   : 465,833
-- game_search : 343,591
-- login       : 246,881
-- app_open    : 143,695
--
-- these categories account for all 1.2 million abandoned journeys.


-- ============================================================
-- 4. drop-off rate by last event
-- ============================================================

-- calculate how many journeys reached each event and compare
-- this with the number of abandoned journeys whose last
-- recorded event was that event.
--
-- this should be interpreted as drop-off by last event,
-- not as a classical sequential funnel.

with reached as (
    select
        event_type,
        count(distinct journey_id) as reached_journeys
    from product_events
    group by event_type
),
abandoned as (
    select
        journey_id,
        event_type,
        event_timestamp,
        row_number() over (
            partition by journey_id
            order by event_timestamp desc
        ) as rn
    from product_events
    where gaming_session_id is null
),
abandoned_group as (
    select
        event_type,
        count(journey_id) as abandoned_journeys
    from abandoned
    where rn = 1
    group by event_type
)
select
    r.event_type,
    r.reached_journeys,
    ag.abandoned_journeys,
    round(
        100.0 * ag.abandoned_journeys / r.reached_journeys,
        2
    ) as drop_off_rate
from reached r
join abandoned_group ag
    on r.event_type = ag.event_type
order by drop_off_rate desc;


-- findings:
--
-- event         reached journeys    abandoned journeys    drop-off rate
-- game_view       4,060,894            465,833            11.47%
-- game_search     3,159,803            343,591            10.87%
-- login           4,335,502            246,881             5.69%
-- app_open        5,200,000            143,695             2.76%
--
-- game_view has the highest last-event drop-off rate at 11.47%.
-- however, these rates should not be interpreted as sequential
-- step-to-step funnel conversion because users can follow
-- different event paths.


-- ============================================================
-- 5. validation of the funnel hypothesis
-- ============================================================

-- check whether game_view is present in every successful journey

select
    count(distinct journey_id) as successful_journeys_with_game_view
from product_events
where gaming_session_id is not null
    and event_type = 'game_view';


-- result: 3,521,145
--
-- only 3,521,145 of 4,000,000 successful journeys contain
-- game_view. therefore, game_view is not a mandatory step
-- before starting a gaming session.


-- check whether app_open is present in every successful journey

select
    count(distinct journey_id) as successful_journeys_with_app_open
from product_events
where gaming_session_id is not null
    and event_type = 'app_open';


-- result: 4,000,000
--
-- all successful journeys contain app_open.
-- therefore, the only robust high-level funnel supported by
-- the data is:
--
-- app_open -> gaming_session
--
-- 5,200,000 journeys -> 4,000,000 successful journeys
-- overall conversion: 76.92%


-- ============================================================
-- 6. user journey path analysis
-- ============================================================

-- because login, game_search and game_view are not mandatory
-- sequential steps, analyse complete event paths instead.
--
-- string_agg is used to reconstruct the chronological event
-- sequence for each journey.
--
-- success = 1 if the journey is linked to a gaming session,
-- otherwise success = 0.

with journey_path as (
    select
        journey_id,
        string_agg(
            event_type,
            ',' order by event_timestamp
        ) as path,
        max(
            case
                when gaming_session_id is not null then 1
                else 0
            end
        ) as success
    from product_events
    group by journey_id
),
path_count as (
    select
        path,
        count(journey_id) as journeys,
        sum(success) as successful_journeys
    from journey_path
    group by path
)
select
    path,
    journeys,
    successful_journeys,
    round(
        100.0 * successful_journeys / journeys,
        2
    ) as conversion_rate
from path_count
order by journeys desc;


-- findings:
--
-- the dataset contains 20 distinct event paths, with most
-- journeys concentrated in a small number of patterns.
--
-- largest paths:
--
-- app_open -> login -> game_search -> game_view
-- 1,820,538 journeys
-- 77.32% conversion
--
-- app_open -> login -> game_view
-- 1,020,847 journeys
-- 100.00% conversion
--
-- app_open -> login -> game_search
-- 461,532 journeys
-- 41.39% conversion
--
-- app_open -> game_search -> game_view
-- 368,086 journeys
-- 100.00% conversion
--
-- app_open -> login
-- 354,385 journeys
-- 39.07% conversion
--
-- app_open
-- 180,360 journeys
-- 20.33% conversion
--
-- conversion varies substantially across different event paths.
-- event ordering is also associated with different conversion
-- outcomes.
--
-- these results show association rather than causation and do
-- not establish that a particular event causes higher or lower
-- conversion.


-- ============================================================
-- 7. path analysis validation
-- ============================================================

-- validate that journey aggregation did not lose or duplicate
-- journeys and successful outcomes.

with journey_path as (
    select
        journey_id,
        string_agg(
            event_type,
            ',' order by event_timestamp
        ) as path,
        max(
            case
                when gaming_session_id is not null then 1
                else 0
            end
        ) as success
    from product_events
    group by journey_id
),
path_count as (
    select
        path,
        count(journey_id) as journeys,
        sum(success) as successful_journeys
    from journey_path
    group by path
)
select
    sum(journeys) as total_journeys,
    sum(successful_journeys) as successful_journeys
from path_count;


-- validation results:
-- total journeys      = 5,200,000
-- successful journeys = 4,000,000
--
-- both totals reconcile with the original journey-level counts.


-- ============================================================
-- 8. conclusions and limitations
-- ============================================================

-- conclusions:
--
-- 1. overall journey-to-gaming-session conversion is 76.92%.
--
-- 2. 1.2 million of 5.2 million journeys were abandoned before
--    starting a gaming session.
--
-- 3. the original sequential funnel hypothesis was not supported
--    by the event data. login, game_search and game_view are not
--    mandatory steps.
--
-- 4. game_view represents the largest last-event abandonment
--    group (465,833 journeys) and the highest last-event
--    drop-off rate among the analysed events (11.47%).
--
-- 5. user behaviour is better represented by multiple journey
--    paths than by a single strict funnel.
--
-- 6. conversion differs substantially across the most common
--    journey paths, suggesting that event sequence is an
--    important dimension for further product analysis.
--
-- limitations:
--
-- 1. drop-off rates represent abandonment by last recorded event,
--    not sequential step-to-step funnel conversion.
--
-- 2. gaming_session_id is used as the definition of successful
--    conversion. session_end is not used because it describes
--    session completion rather than session start/conversion.
--
-- 3. several very low-volume journeys contain unusual event
--    ordering, including events occurring before app_open.
--    these records were preserved rather than removed.
--
-- 4. differences in conversion between paths are observational
--    associations and should not be interpreted as causal effects.
--
-- 5. the dataset is synthetic and was designed to simulate
--    product behaviour in a cloud gaming subscription service.