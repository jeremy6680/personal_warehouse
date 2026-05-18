-- ============================================================
-- Model: stg_spotify__saved_albums
-- Layer: Staging
-- Description: Spotify saved albums, cleaned and typed.
--              album_id is Spotify's native stable ID — no surrogate key needed.
--              Note: genres is almost always an empty JSON array ([]) — Spotify
--              stores genres on Artist objects, not Album objects. Enrich via
--              stg_spotify__followed_artists if genre data is needed.
-- Source: spotify.spotify_saved_albums
-- Adapter note: BigQuery only (SAFE_CAST).
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('spotify', 'spotify_saved_albums') }}
),

renamed AS (
    SELECT
        cast(album_id AS STRING) AS album_id,
        name AS album_name,
        artists,
        artist_ids,
        release_date,
        release_date_precision,
        genres,
        added_at,
        _extracted_at,
        safe_cast(total_tracks AS INT64) AS total_tracks
    FROM source
)

SELECT * FROM renamed
