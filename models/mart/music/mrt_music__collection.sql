-- ============================================================
-- Model: mrt_music__collection
-- Layer: Mart
-- Description: Full album collection from MusicBuddy, enriched with country.
--              artist is the display name (Discogs disambiguation suffix stripped).
--              rating is null for unrated albums (MusicBuddy uses 0 for unrated).
-- Dependencies: int_music__collection
-- Adapter note: Standard SQL — works on BigQuery, DuckDB, and PostgreSQL.
-- ============================================================

{{ config(
    materialized='table',
    tags=['mart', 'music']
) }}

WITH

source_data AS (
    SELECT * FROM {{ ref('int_music__collection') }}
),

collection AS (
    SELECT
        album_id,
        title,
        artist_display                                              AS artist,
        genres,
        release_year,
        discogs_release_id,
        NULLIF(rating, 0)                                           AS rating,
        country,
        'musicbuddy'                                                AS source
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL                                          AS is_rated
    FROM collection
)

SELECT * FROM with_flags
