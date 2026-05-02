-- ============================================================
-- Model: stg_csv__bookbuddy
-- Layer: Staging
-- Description: BookBuddy collection export, cleaned and typed.
--              Selects relevant fields, renames to snake_case, casts rating.
-- Source: csv.bookbuddy
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
        nullif(trim(CAST(`Tags` AS STRING)), '')                                           AS tags
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'author']) }} AS book_id,
        *
    FROM renamed
)

SELECT * FROM with_id
