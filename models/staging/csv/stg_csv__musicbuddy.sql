-- ============================================================
-- Model: stg_csv__musicbuddy
-- Layer: Staging
-- Description: MusicBuddy collection export, cleaned and typed.
--              Selects relevant fields, renames to snake_case, casts release year and rating.
--              Surrogate key includes discogs_release_id to distinguish different releases
--              of the same album (e.g. two self-titled Weezer albums, album vs single).
--              Deduplicates on that key keeping the latest-added row to handle
--              data-entry duplicates.
-- Source: csv.musicbuddy
-- Adapter note: QUALIFY and EXCEPT require BigQuery or DuckDB.
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
        safe_cast(`Rating` AS FLOAT64)            AS rating,
        CAST(`Date Added` AS STRING)              AS _date_added
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'artist', 'discogs_release_id']) }} AS album_id,
        *
    FROM renamed
),

deduped AS (
    SELECT * EXCEPT (_date_added)
    FROM with_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY album_id ORDER BY _date_added DESC) = 1
)

SELECT * FROM deduped
