-- ============================================================
-- Model: mrt_movies__collection
-- Layer: Mart
-- Description: Full movie collection — watched and wishlist items.
--              Rating is resolved upstream in int_movies__unified with priority:
--              Trakt > Letterboxd > MovieBuddy > manual fallback.
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
        first_watched_date,
        last_watched_date,
        rating,
        directors,
        genres,
        runtime_minutes,
        tmdb_id,
        letterboxd_uri,
        country,
        source,
        first_watched_date IS NOT NULL AS is_watched
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL AS is_rated
    FROM collection
)

SELECT * FROM with_flags
