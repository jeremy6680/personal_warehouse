-- ============================================================
-- Model: stg_trakt__ratings
-- Layer: Staging
-- Description: Trakt movie and show ratings, cleaned and typed.
--              Trakt raw ratings are 1-10; rating is normalized to 0.5-5.
-- Source: trakt.trakt_ratings
-- Adapter note: BigQuery only (SAFE_CAST).
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('trakt', 'trakt_ratings') }}
),

renamed AS (
    SELECT
        CAST(media_type AS STRING)                AS media_type,
        SAFE_CAST(trakt_id AS INT64)              AS trakt_id,
        CAST(slug AS STRING)                      AS slug,
        CAST(imdb_id AS STRING)                   AS imdb_id,
        SAFE_CAST(tmdb_id AS INT64)               AS tmdb_id,
        trim(title)                               AS title,
        SAFE_CAST(release_year AS INT64)          AS release_year,
        SAFE_CAST(rating_raw AS INT64)            AS rating_raw,
        SAFE_CAST(rating AS FLOAT64)              AS rating,
        SAFE_CAST(rated_at AS TIMESTAMP)          AS rated_at,
        CAST(genres AS STRING)                    AS genres,
        SAFE_CAST(runtime_minutes AS INT64)       AS runtime_minutes,
        CAST(country AS STRING)                   AS country,
        SAFE_CAST(_extracted_at AS TIMESTAMP)     AS _extracted_at
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['media_type', 'title', 'release_year']) }} AS rating_id,
        *
    FROM renamed
)

SELECT * FROM with_id
