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
        cast(item_type AS STRING) AS item_type,
        cast(tralbum_type AS STRING) AS tralbum_type,
        cast(item_url AS STRING) AS item_url,
        cast(art_url AS STRING) AS art_url,
        cast(token AS STRING) AS token,
        cast(added_at AS STRING) AS added_at,
        cast(raw_json AS STRING) AS raw_json,
        safe_cast(item_id AS INT64) AS item_id,
        safe_cast(tralbum_id AS INT64) AS tralbum_id,
        nullif(trim(title), '') AS title,
        nullif(trim(artist), '') AS artist,
        safe_cast(_extracted_at AS TIMESTAMP) AS _extracted_at
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
    QUALIFY row_number() OVER (
        PARTITION BY album_id
        ORDER BY _extracted_at DESC
    ) = 1
)

SELECT * FROM deduped
