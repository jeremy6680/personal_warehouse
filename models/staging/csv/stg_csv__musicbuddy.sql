-- ============================================================
-- Model: stg_csv__musicbuddy
-- Layer: Staging
-- Description: MusicBuddy collection export, cleaned and typed.
--              Selects relevant fields, renames to snake_case, casts release year and rating.
-- Source: csv.musicbuddy
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('csv', 'musicbuddy') }}
),

renamed AS (
    SELECT
        trim(`Title`)                             AS title,
        trim(`Artist`)                            AS artist,
        nullif(trim(`Genres`), '')                AS genres,
        safe_cast(`Release Year` AS INT64)        AS release_year,
        safe_cast(`discogs Release ID` AS INT64)  AS discogs_release_id,
        safe_cast(`Rating` AS FLOAT64)            AS rating
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'artist']) }} AS album_id,
        *
    FROM renamed
)

SELECT * FROM with_id
