-- ============================================================
-- Model: stg_csv__letterboxd
-- Layer: Staging
-- Description: Letterboxd diary export, cleaned and typed.
--              Renames columns to snake_case, casts date and rating.
-- Source: csv.letterboxd
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('csv', 'letterboxd') }}
),

renamed AS (
    SELECT
        safe_cast(`Date` AS DATE)             AS watched_date,
        trim(`Name`)                          AS film_name,
        safe_cast(`Year` AS INT64)            AS release_year,
        trim(`Letterboxd URI`)                AS letterboxd_uri,
        safe_cast(`Rating` AS FLOAT64)        AS rating
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['watched_date', 'film_name']) }} AS movie_id,
        *
    FROM renamed
)

SELECT * FROM with_id
