-- ============================================================
-- Model: mrt_anime__collection
-- Layer: Mart
-- Description: Anime collection from Trakt and MovieBuddy animated TV shows.
-- Dependencies: int_anime__unified
-- Adapter note: Standard SQL.
-- ============================================================

{{ config(
    materialized='table',
    tags=['mart', 'anime']
) }}

WITH

source_data AS (
    SELECT * FROM {{ ref('int_anime__unified') }}
),

collection AS (
    SELECT
        anime_id,
        title,
        content_type,
        release_year,
        last_watched_date IS NOT NULL  AS is_watched,
        first_watched_date,
        last_watched_date,
        rating,
        directors,
        genres,
        runtime_minutes,
        tmdb_id,
        country,
        source
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL AS is_rated
    FROM collection
)

SELECT * FROM with_flags
