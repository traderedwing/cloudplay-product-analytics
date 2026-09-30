-- ============================================================
-- 01. database setup
-- CloudPlay Product Analytics
-- ============================================================

-- This script documents the PostgreSQL schema used for the
-- CloudPlay analytics project.
--
-- The dataset is synthetic and simulates a cloud gaming
-- subscription product.


-- ============================================================
-- 1. users
-- ============================================================

create table users (
    user_id bigint primary key,
    signup_date date,
    country varchar,
    acquisition_channel varchar,
    signup_device varchar,
    birth_year integer
);


-- ============================================================
-- 2. subscriptions
-- ============================================================

create table subscriptions (
    subscription_id bigint primary key,
    user_id bigint,
    plan varchar,
    subscription_start_date date,
    subscription_end_date date,
    status varchar,
    cancellation_reason varchar,

    constraint fk_subscriptions_user
        foreign key (user_id)
        references users(user_id)
);


-- ============================================================
-- 3. payments
-- ============================================================

create table payments (
    payment_id bigint primary key,
    subscription_id bigint,
    user_id bigint,
    payment_date date,
    amount numeric(10,2),
    currency varchar,
    payment_status varchar,
    payment_method varchar,
    refund_amount numeric(10,2),

    constraint fk_payments_subscription
        foreign key (subscription_id)
        references subscriptions(subscription_id),

    constraint fk_payments_user
        foreign key (user_id)
        references users(user_id)
);


-- ============================================================
-- 4. gaming sessions
-- ============================================================

create table gaming_sessions (
    session_id bigint primary key,
    user_id bigint,
    game_id bigint,
    session_start timestamp,
    session_end timestamp,
    device varchar,
    server_region varchar,
    queue_time_seconds integer,
    avg_latency_ms numeric,
    avg_fps numeric,
    disconnect_flag boolean,

    constraint fk_gaming_sessions_user
        foreign key (user_id)
        references users(user_id)
);


-- ============================================================
-- 5. events
-- ============================================================

create table events (
    event_id bigint primary key,
    user_id bigint,
    event_timestamp timestamp,
    event_type varchar,
    gaming_session_id bigint,
    game_id bigint,
    device varchar,

    constraint fk_events_user
        foreign key (user_id)
        references users(user_id)
);


-- ============================================================
-- 6. product events
-- ============================================================

create table product_events (
    event_id bigint primary key,
    user_id bigint,
    event_timestamp timestamp,
    event_type varchar,
    journey_id bigint,
    gaming_session_id bigint,
    game_id bigint,
    device varchar,

    constraint fk_product_events_user
        foreign key (user_id)
        references users(user_id)
);


-- ============================================================
-- 7. indexes
-- ============================================================

-- Indexes support joins and analytical queries on frequently
-- used identifiers and timestamps.

create index idx_subscriptions_user_id
    on subscriptions(user_id);

create index idx_payments_user_id
    on payments(user_id);

create index idx_payments_subscription_id
    on payments(subscription_id);

create index idx_gaming_sessions_user_id
    on gaming_sessions(user_id);

create index idx_events_user_id
    on events(user_id);

create index idx_product_events_user_id
    on product_events(user_id);

create index idx_product_events_journey_id
    on product_events(journey_id);


-- ============================================================
-- schema summary
-- ============================================================

-- users            -> customer-level attributes
-- subscriptions    -> subscription lifecycle
-- payments         -> billing and monetization
-- gaming_sessions  -> gameplay and technical experience
-- events           -> general behavioural events
-- product_events   -> product journeys and funnel behaviour