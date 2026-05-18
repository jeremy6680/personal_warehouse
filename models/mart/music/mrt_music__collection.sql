-- ============================================================
-- Model: mrt_music__collection
-- Layer: Mart
-- Description: Full music library from listened/liked sources: MusicBuddy,
--              Bandcamp collection/wishlist, and Spotify, enriched with country.
--              artist_display is used for MusicBuddy rows (Discogs suffix stripped);
--              Bandcamp/Spotify-only rows use the raw artists string.
--              rating is null for unrated albums (MusicBuddy uses 0 for unrated;
--              Spotify carries no personal rating).
--              source_name tracks the contributing source or source combination.
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
        artist_display AS artist,
        genres,
        release_year,
        discogs_release_id,
        spotify_album_id,
        total_tracks,
        spotify_added_at,
        bandcamp_item_id,
        bandcamp_item_url,
        bandcamp_added_at,
        bandcamp_origin,
        country,
        source_name,
        media_format,
        nullif(rating, 0) AS rating
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL AS is_rated
    FROM collection
)

SELECT * FROM with_flags
