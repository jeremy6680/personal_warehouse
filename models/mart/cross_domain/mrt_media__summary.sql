-- ============================================================
-- Model: mrt_media__summary
-- Layer: Mart
-- Description: Cross-domain aggregate — one row per media domain. Summarises
--              total item counts, consumed vs. pending items (read for books,
--              watched for movies/anime; null for music and manga which have no
--              consumption tracking), rated item counts, average unified rating,
--              and country coverage.
--              Note: all books in the collection are considered read (ADR-025).
-- Dependencies: mrt_books__collection, mrt_movies__collection,
--               mrt_music__collection, mrt_manga__collection,
--               mrt_anime__collection
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

manga AS (
    SELECT * FROM {{ ref('mrt_manga__collection') }}
),

anime AS (
    SELECT * FROM {{ ref('mrt_anime__collection') }}
),

books_summary AS (
    SELECT
        'books' AS domain,
        count(*) AS total_items,
        -- All books in the collection are read (ADR-025)
        count(*) AS items_consumed,
        cast(0 AS INT64) AS items_pending,
        countif(is_rated) AS items_rated,
        round(avg(rating), 2) AS avg_rating,
        countif(country IS NOT NULL) AS items_with_country
    FROM books
),

movies_summary AS (
    SELECT
        'movies' AS domain,
        count(*) AS total_items,
        countif(is_watched) AS items_consumed,
        countif(NOT is_watched) AS items_pending,
        countif(is_rated) AS items_rated,
        round(avg(rating), 2) AS avg_rating,
        countif(country IS NOT NULL) AS items_with_country
    FROM movies
),

music_summary AS (
    SELECT
        'music' AS domain,
        count(*) AS total_items,
        cast(NULL AS INT64) AS items_consumed,
        cast(NULL AS INT64) AS items_pending,
        countif(is_rated) AS items_rated,
        round(avg(rating), 2) AS avg_rating,
        countif(country IS NOT NULL) AS items_with_country
    FROM music
),

manga_summary AS (
    SELECT
        'manga' AS domain,
        count(*) AS total_items,
        cast(NULL AS INT64) AS items_consumed,
        cast(NULL AS INT64) AS items_pending,
        countif(is_rated) AS items_rated,
        round(avg(rating), 2) AS avg_rating,
        countif(country IS NOT NULL) AS items_with_country
    FROM manga
),

anime_summary AS (
    SELECT
        'anime' AS domain,
        count(*) AS total_items,
        countif(is_watched) AS items_consumed,
        countif(NOT is_watched) AS items_pending,
        countif(is_rated) AS items_rated,
        round(avg(rating), 2) AS avg_rating,
        countif(country IS NOT NULL) AS items_with_country
    FROM anime
),

combined AS (
    SELECT * FROM books_summary
    UNION ALL
    SELECT * FROM movies_summary
    UNION ALL
    SELECT * FROM music_summary
    UNION ALL
    SELECT * FROM manga_summary
    UNION ALL
    SELECT * FROM anime_summary
)

SELECT * FROM combined
