-- ============================================================
-- Model: stg_spotify__saved_tracks
-- Layer: Staging
-- Description: Spotify saved tracks, cleaned and typed.
--              track_id is Spotify's native stable ID — no surrogate key needed.
--              Audio feature columns (danceability, energy, etc.) are cast from
--              STRING to FLOAT64 — BQ autodetect inferred STRING because all values
--              were NULL at load time (Spotify deprecated the /audio-features endpoint
--              for new applications in November 2024).
-- Source: spotify.spotify_saved_tracks
-- Adapter note: BigQuery only (SAFE_CAST).
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('spotify', 'spotify_saved_tracks') }}
),

renamed AS (
    SELECT
        track_id,
        name                                    AS track_name,
        artists,
        artist_ids,
        album_id,
        album_name,
        duration_ms,
        explicit,
        SAFE_CAST(popularity AS INT64)          AS popularity,
        added_at,
        -- Audio features — NULL for new Spotify applications (endpoint deprecated Nov 2024)
        SAFE_CAST(danceability AS FLOAT64)      AS danceability,
        SAFE_CAST(energy AS FLOAT64)            AS energy,
        SAFE_CAST(valence AS FLOAT64)           AS valence,
        SAFE_CAST(tempo AS FLOAT64)             AS tempo,
        SAFE_CAST(acousticness AS FLOAT64)      AS acousticness,
        SAFE_CAST(instrumentalness AS FLOAT64)  AS instrumentalness,
        SAFE_CAST(liveness AS FLOAT64)          AS liveness,
        SAFE_CAST(speechiness AS FLOAT64)       AS speechiness,
        _extracted_at
    FROM source
)

SELECT * FROM renamed
