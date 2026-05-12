-- ============================================================
-- Model: stg_csv__bandcamp_wishlist
-- Layer: Staging
-- Description: Bandcamp wishlist from the internal fan collection API, cleaned
--              and typed. raw_json is preserved because the API is undocumented
--              and fields can change without notice (ADR-018).
-- Source: csv.bandcamp_wishlist
-- Adapter note: BigQuery only (SAFE_CAST).
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('csv', 'bandcamp_wishlist') }}
),

renamed AS (
    SELECT
        SAFE_CAST(item_id AS INT64)         AS item_id,
        CAST(item_type AS STRING)           AS item_type,
        SAFE_CAST(tralbum_id AS INT64)      AS tralbum_id,
        CAST(tralbum_type AS STRING)        AS tralbum_type,
        NULLIF(trim(title), '')             AS title,
        NULLIF(trim(artist), '')            AS artist,
        CAST(item_url AS STRING)            AS item_url,
        CAST(art_url AS STRING)             AS art_url,
        CAST(token AS STRING)               AS token,
        CAST(added_at AS STRING)            AS added_at,
        CAST(raw_json AS STRING)            AS raw_json,
        SAFE_CAST(_extracted_at AS TIMESTAMP) AS _extracted_at
    FROM source
),

with_id AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['title', 'artist', 'item_url']) }} AS album_id,
        *
    FROM renamed
),

deduped AS (
    SELECT *
    FROM with_id
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY album_id
        ORDER BY _extracted_at DESC
    ) = 1
)

SELECT * FROM deduped
