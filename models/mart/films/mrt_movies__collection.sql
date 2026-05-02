-- ============================================================
-- Model: mrt_movies__collection
-- Layer: Mart
-- Description: Full movie and TV show collection — watched and wishlist items.
--              Single unified rating: Letterboxd is the source of truth when both
--              sources have a rating, otherwise MovieBuddy rating is used.
--              source indicates which app(s) contributed the row.
-- Dependencies: int_movies__unified
-- Adapter note: SPLIT/SAFE_OFFSET is BigQuery/DuckDB — for PostgreSQL use split_part().
--               Standard SQL otherwise.
-- ============================================================

{{ config(
    materialized='table',
    tags=['mart', 'movies']
) }}

WITH

source_data AS (
    SELECT * FROM {{ ref('int_movies__unified') }}
),

collection AS (
    SELECT
        movie_id,
        title,
        content_type,
        release_year,
        first_watched_date IS NOT NULL                              AS is_watched,
        first_watched_date,
        last_watched_date,
        -- Letterboxd is source of truth for rating; fall back to MovieBuddy (0 = unrated)
        COALESCE(
            letterboxd_rating,
            NULLIF(rating, 0)
        )                                                           AS rating,
        directors,
        genres,
        runtime_minutes,
        tmdb_id,
        letterboxd_uri,
        country,
        CASE
            WHEN match_type IS NOT NULL      THEN 'moviebuddy_and_letterboxd'
            WHEN letterboxd_uri IS NOT NULL  THEN 'letterboxd'
            ELSE                                  'moviebuddy'
        END                                                         AS source
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL                                          AS is_rated
    FROM collection
)

SELECT * FROM with_flags
