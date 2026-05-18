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
        name AS track_name,
        artists,
        artist_ids,
        album_id,
        album_name,
        duration_ms,
        explicit,
        added_at,
        _extracted_at,
        -- Audio features — NULL for new Spotify applications (endpoint deprecated Nov 2024)
        safe_cast(popularity AS INT64) AS popularity,
        safe_cast(danceability AS FLOAT64) AS danceability,
        safe_cast(energy AS FLOAT64) AS energy,
        safe_cast(valence AS FLOAT64) AS valence,
        safe_cast(tempo AS FLOAT64) AS tempo,
        safe_cast(acousticness AS FLOAT64) AS acousticness,
        safe_cast(instrumentalness AS FLOAT64) AS instrumentalness,
        safe_cast(liveness AS FLOAT64) AS liveness,
        safe_cast(speechiness AS FLOAT64) AS speechiness
    FROM source
)

SELECT * FROM renamed
