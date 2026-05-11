-- ============================================================
-- Model: mrt_music__collection
-- Layer: Mart
-- Description: Full album collection from MusicBuddy and Spotify, enriched
--              with country. One row per album across both sources.
--              artist_display is used for MusicBuddy rows (Discogs suffix stripped);
--              Spotify-only rows use the raw artists string.
--              rating is null for unrated albums (MusicBuddy uses 0 for unrated;
--              Spotify carries no personal rating).
--              source_name: 'musicbuddy' | 'spotify' | 'both'
--              media_format: 'cd' | 'digital' | 'cd, digital' (ADR-021)
-- Dependencies: int_music__unified
-- Adapter note: Standard SQL — works on BigQuery, DuckDB, and PostgreSQL.
-- ============================================================

{{ config(
    materialized='table',
    tags=['mart', 'music']
) }}

WITH

source_data AS (
    SELECT * FROM {{ ref('int_music__unified') }}
),

collection AS (
    SELECT
        album_id,
        title,
        artist_display                  AS artist,
        genres,
        release_year,
        discogs_release_id,
        spotify_album_id,
        total_tracks,
        spotify_added_at,
        NULLIF(rating, 0)               AS rating,
        country,
        source_name,
        media_format
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL              AS is_rated
    FROM collection
)

SELECT * FROM with_flags