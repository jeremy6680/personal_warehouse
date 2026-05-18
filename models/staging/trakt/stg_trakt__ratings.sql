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
        cast(media_type AS STRING) AS media_type,
        cast(slug AS STRING) AS slug,
        cast(imdb_id AS STRING) AS imdb_id,
        cast(genres AS STRING) AS genres,
        cast(country AS STRING) AS country,
        safe_cast(trakt_id AS INT64) AS trakt_id,
        safe_cast(tmdb_id AS INT64) AS tmdb_id,
        trim(title) AS title,
        safe_cast(release_year AS INT64) AS release_year,
        safe_cast(rating_raw AS INT64) AS rating_raw,
        safe_cast(rating AS FLOAT64) AS rating,
        safe_cast(rated_at AS TIMESTAMP) AS rated_at,
        safe_cast(runtime_minutes AS INT64) AS runtime_minutes,
        safe_cast(_extracted_at AS TIMESTAMP) AS _extracted_at
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['media_type', 'title', 'release_year']) }} AS rating_id,
        *
    FROM renamed
)

SELECT * FROM with_id
