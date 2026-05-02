-- ============================================================
-- Model: stg_csv__moviebuddy
-- Layer: Staging
-- Description: MovieBuddy collection export, cleaned and typed.
--              Selects relevant fields, renames to snake_case, casts rating.
-- Source: csv.moviebuddy
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('csv', 'moviebuddy') }}
),

renamed AS (
    SELECT
        trim(`Title`)                                                                      AS title,
        trim(`Content Type`)                                                               AS content_type,
        safe_cast(`Release Year` AS INT64)                                                 AS release_year,
        safe_cast(`Rating` AS FLOAT64)                                                     AS rating,
        nullif(trim(`Directors`), '')                                                      AS directors,
        nullif(trim(`Genres`), '')                                                         AS genres,
        safe_cast(`Runtime` AS INT64)                                                      AS runtime_minutes,
        safe_cast(`TMDB ID` AS INT64)                                                      AS tmdb_id
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'release_year']) }} AS movie_id,
        *
    FROM renamed
)

SELECT * FROM with_id
