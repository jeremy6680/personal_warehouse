-- ============================================================
-- Model: mrt_media__summary
-- Layer: Mart
-- Description: Cross-domain aggregate — one row per media domain (books, movies,
--              music). Summarises total item counts, consumed vs. pending items
--              (read for books, watched for movies; null for music which has no
--              consumption tracking), rated item counts, average unified rating,
--              and country coverage.
-- Dependencies: mrt_books__collection, mrt_movies__collection, mrt_music__collection
-- Adapter note: COUNTIF is BigQuery-specific. For DuckDB/PostgreSQL replace with
--               SUM(CASE WHEN <condition> THEN 1 ELSE 0 END).
-- ============================================================

{{ config(
    materialized='table',
    tags=['mart', 'cross_domain']
) }}

WITH

books AS (
    SELECT * FROM {{ ref('mrt_books__collection') }}
),

movies AS (
    SELECT * FROM {{ ref('mrt_movies__collection') }}
),

music AS (
    SELECT * FROM {{ ref('mrt_music__collection') }}
),

books_summary AS (
    SELECT
        'books'                              AS domain,
        COUNT(*)                             AS total_items,
        COUNTIF(is_read)                     AS items_consumed,
        COUNTIF(NOT is_read)                 AS items_pending,
        COUNTIF(is_rated)                    AS items_rated,
        ROUND(AVG(rating), 2)               AS avg_rating,
        COUNTIF(country IS NOT NULL)         AS items_with_country
    FROM books
),

movies_summary AS (
    SELECT
        'movies'                             AS domain,
        COUNT(*)                             AS total_items,
        COUNTIF(is_watched)                  AS items_consumed,
        COUNTIF(NOT is_watched)              AS items_pending,
        COUNTIF(is_rated)                    AS items_rated,
        ROUND(AVG(rating), 2)               AS avg_rating,
        COUNTIF(country IS NOT NULL)         AS items_with_country
    FROM movies
),

music_summary AS (
    SELECT
        'music'                              AS domain,
        COUNT(*)                             AS total_items,
        CAST(NULL AS INT64)                  AS items_consumed,
        CAST(NULL AS INT64)                  AS items_pending,
        COUNTIF(is_rated)                    AS items_rated,
        ROUND(AVG(rating), 2)               AS avg_rating,
        COUNTIF(country IS NOT NULL)         AS items_with_country
    FROM music
),

combined AS (
    SELECT * FROM books_summary
    UNION ALL
    SELECT * FROM movies_summary
    UNION ALL
    SELECT * FROM music_summary
)

SELECT * FROM combined
