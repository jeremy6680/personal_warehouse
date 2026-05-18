-- ============================================================
-- Model: stg_spotify__followed_artists
-- Layer: Staging
-- Description: Spotify followed artists, cleaned and typed.
--              artist_id is Spotify's native stable ID — no surrogate key needed.
--              genres is a JSON array string — reliable on Artist objects (unlike
--              albums where it is almost always empty).
--              popularity and followers cast from STRING: BQ autodetect inferred STRING
--              because the first loaded rows had NULL values.
-- Source: spotify.spotify_followed_artists
-- Adapter note: BigQuery only (SAFE_CAST).
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('spotify', 'spotify_followed_artists') }}
),

renamed AS (
    SELECT
        cast(artist_id AS STRING) AS artist_id,
        name AS artist_name,
        genres,
        _extracted_at,
        safe_cast(popularity AS INT64) AS popularity,
        safe_cast(followers AS INT64) AS followers
    FROM source
)

SELECT * FROM renamed
