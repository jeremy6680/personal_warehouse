-- ============================================================
-- Model: stg_csv__bookbuddy
-- Layer: Staging
-- Description: BookBuddy collection export, cleaned and typed.
--              Selects relevant fields, renames to snake_case, casts rating.
--              Surrogate key includes isbn to distinguish editions of the same
--              title/author. Deduplicates on that key keeping the latest-added
--              row to handle data-entry duplicates.
-- Source: csv.bookbuddy
-- Adapter note: QUALIFY and EXCEPT require BigQuery or DuckDB.
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('csv', 'bookbuddy') }}
),

renamed AS (
    SELECT
        trim(`Title`)                                                                      AS title,
        trim(`Author`)                                                                     AS author,
        nullif(trim(`Genre`), '')                                                          AS genre,
        nullif(trim(`Category`), '')                                                       AS category,
        trim(`Status`)                                                                     AS status,
        safe_cast(`Rating` AS FLOAT64)                                                     AS rating,
        nullif(trim(CAST(`ISBN` AS STRING)), '')                                           AS isbn,
        nullif(trim(CAST(`Tags` AS STRING)), '')                                           AS tags,
        CAST(`Date Added` AS STRING)                                                       AS _date_added
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'author', 'isbn']) }} AS book_id,
        *
    FROM renamed
),

deduped AS (
    SELECT * EXCEPT (_date_added)
    FROM with_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY book_id ORDER BY _date_added DESC) = 1
)

SELECT * FROM deduped
