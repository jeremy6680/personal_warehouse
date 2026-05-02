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
        CAST(`Book Id` AS STRING)                                               AS book_id,
        trim(`Title`)                                                           AS title,
        trim(`Author`)                                                          AS author,
        safe_cast(trim(CAST(`Year Published` AS STRING)) AS INT64)              AS year_published,
        trim(`Publisher`)                                                       AS publisher,
        nullif(regexp_replace(`ISBN`, r'^="?|"$', ''), '')                      AS isbn,
        safe_cast(trim(CAST(`My Rating` AS STRING)) AS INT64)                   AS rating,
        'goodreads'                                                             AS source_name
    FROM source
)

SELECT * FROM renamed
