-- ============================================================
-- Model: mrt_manga__collection
-- Layer: Mart
-- Description: Manga collection sourced from BookBuddy.
-- Dependencies: int_manga__unified
-- Adapter note: Standard SQL.
-- ============================================================

{{ config(
    materialized='table',
    tags=['mart', 'manga']
) }}

WITH

source_data AS (
    SELECT * FROM {{ ref('int_manga__unified') }}
),

collection AS (
    SELECT
        manga_id,
        title,
        author,
        genre,
        category,
        rating,
        isbn,
        tags,
        country,
        source
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL AS is_rated
    FROM collection
)

SELECT * FROM with_flags
