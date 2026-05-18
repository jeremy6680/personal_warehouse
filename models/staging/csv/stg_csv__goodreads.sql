-- ============================================================
-- Model: stg_csv__goodreads
-- Layer: Staging
-- Description: Goodreads library export, cleaned and typed.
--              Selects relevant fields, renames to snake_case, casts types.
-- Source: csv.goodreads
-- Adapter note: ISBN column is stored as Excel-quoted string (="...") —
--               regexp_replace strips the surrounding ="..." wrapper.
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('csv', 'goodreads') }}
),

renamed AS (
    SELECT
        cast(`Book Id` AS STRING) AS book_id,
        'goodreads' AS source_name,
        trim(`Title`) AS title,
        trim(`Author`) AS author,
        safe_cast(trim(cast(`Year Published` AS STRING)) AS INT64) AS year_published,
        trim(`Publisher`) AS publisher,
        nullif(regexp_replace(isbn, r'^="?|"$', ''), '') AS isbn,
        safe_cast(trim(cast(`My Rating` AS STRING)) AS INT64) AS rating
    FROM source
)

SELECT * FROM renamed
