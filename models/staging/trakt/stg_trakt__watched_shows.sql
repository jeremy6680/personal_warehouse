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
        cast(slug AS STRING) AS slug,
        cast(imdb_id AS STRING) AS imdb_id,
        cast(genres AS STRING) AS genres,
        cast(status AS STRING) AS status,
        cast(network AS STRING) AS network,
        cast(country AS STRING) AS country,
        safe_cast(trakt_show_id AS INT64) AS trakt_show_id,
        safe_cast(tmdb_id AS INT64) AS tmdb_id,
        trim(title) AS title,
        safe_cast(release_year AS INT64) AS release_year,
        safe_cast(plays AS INT64) AS watch_count,
        safe_cast(last_watched_at AS TIMESTAMP) AS last_watched_at,
        safe_cast(last_updated_at AS TIMESTAMP) AS last_updated_at,
        safe_cast(runtime_minutes AS INT64) AS runtime_minutes,
        safe_cast(_extracted_at AS TIMESTAMP) AS _extracted_at
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'release_year']) }} AS show_id,
        *
    FROM renamed
)

SELECT * FROM with_id
