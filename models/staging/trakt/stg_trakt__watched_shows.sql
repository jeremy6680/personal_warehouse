-- ============================================================
-- Model: stg_trakt__watched_shows
-- Layer: Staging
-- Description: Trakt watched shows, cleaned and typed.
-- Source: trakt.trakt_watched_shows
-- Adapter note: BigQuery only (SAFE_CAST).
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('trakt', 'trakt_watched_shows') }}
),

renamed AS (
    SELECT
        SAFE_CAST(trakt_show_id AS INT64)         AS trakt_show_id,
        CAST(slug AS STRING)                      AS slug,
        CAST(imdb_id AS STRING)                   AS imdb_id,
        SAFE_CAST(tmdb_id AS INT64)               AS tmdb_id,
        trim(title)                               AS title,
        SAFE_CAST(release_year AS INT64)          AS release_year,
        SAFE_CAST(plays AS INT64)                 AS watch_count,
        SAFE_CAST(last_watched_at AS TIMESTAMP)   AS last_watched_at,
        SAFE_CAST(last_updated_at AS TIMESTAMP)   AS last_updated_at,
        CAST(genres AS STRING)                    AS genres,
        SAFE_CAST(runtime_minutes AS INT64)       AS runtime_minutes,
        CAST(status AS STRING)                    AS status,
        CAST(network AS STRING)                   AS network,
        CAST(country AS STRING)                   AS country,
        SAFE_CAST(_extracted_at AS TIMESTAMP)     AS _extracted_at
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'release_year']) }} AS show_id,
        *
    FROM renamed
)

SELECT * FROM with_id
