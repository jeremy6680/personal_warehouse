-- ============================================================
-- Model: mrt_media__country_index
-- Layer: Mart
-- Description: Cross-domain country spine — one row per (country, domain, item).
--              Links each country to all books, films, and albums associated with
--              it. person_name is the author (books), primary director (movies),
--              or artist (music). person_role identifies the type of person.
--              Only rows with a known country are included.
--              Enables queries like "show me all French media" without joining
--              across three separate mart tables.
-- Dependencies: mrt_books__collection, mrt_movies__collection, mrt_music__collection
-- Adapter note: SPLIT/SAFE_OFFSET is BigQuery-specific (for primary director).
--               For PostgreSQL replace with split_part(directors, ',', 1).
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

books_spine AS (
    SELECT
        country,
        'books'       AS domain,
        book_id       AS item_id,
        title         AS item_title,
        author        AS person_name,
        'author'      AS person_role,
        rating
    FROM books
    WHERE country IS NOT NULL
),

movies_spine AS (
    SELECT
        country,
        'movies'                                                    AS domain,
        movie_id                                                    AS item_id,
        title                                                       AS item_title,
        -- Primary director: first entry in comma-separated list
        -- Adapter note: SPLIT/SAFE_OFFSET is BigQuery — use split_part() on PostgreSQL
        TRIM(SPLIT(directors, ',')[SAFE_OFFSET(0)])                 AS person_name,
        'director'                                                  AS person_role,
        rating
    FROM movies
    WHERE country IS NOT NULL
),

music_spine AS (
    SELECT
        country,
        'music'       AS domain,
        album_id      AS item_id,
        title         AS item_title,
        artist        AS person_name,
        'artist'      AS person_role,
        rating
    FROM music
    WHERE country IS NOT NULL
),

combined AS (
    SELECT * FROM books_spine
    UNION ALL
    SELECT * FROM movies_spine
    UNION ALL
    SELECT * FROM music_spine
)

SELECT * FROM combined
