-- ============================================================
-- Model: mrt_media__country_index
-- Layer: Mart
-- Description: Cross-domain country spine — one row per (country, domain, item).
--              Links each country to all books, films, albums, manga, and anime
--              associated with it. person_name is the author (books/manga),
--              primary director (movies/anime), or artist (music).
--              person_role identifies the type of person.
--              Only rows with a known country are included.
--              iso_alpha3 (ISO 3166-1 alpha-3) is joined from the country_iso_codes
--              seed to enable choropleth map rendering in Evidence.dev.
--              Enables queries like "show me all French media" without joining
--              across three separate mart tables.
-- Dependencies: mrt_books__collection, mrt_movies__collection,
--               mrt_music__collection, mrt_manga__collection,
--               mrt_anime__collection, country_iso_codes (seed)
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

manga AS (
    SELECT * FROM {{ ref('mrt_manga__collection') }}
),

anime AS (
    SELECT * FROM {{ ref('mrt_anime__collection') }}
),

iso_codes AS (
    SELECT
        iso_alpha3,
        lower(trim(country_name)) AS country_key
    FROM {{ ref('country_iso_codes') }}
),

books_spine AS (
    SELECT
        country,
        'books' AS domain,
        book_id AS item_id,
        title AS item_title,
        author AS person_name,
        'author' AS person_role,
        rating
    FROM books
    WHERE country IS NOT NULL
),

movies_spine AS (
    SELECT
        country,
        'movies' AS domain,
        movie_id AS item_id,
        title AS item_title,
        -- Primary director: first entry in comma-separated list
        -- Adapter note: SPLIT/SAFE_OFFSET is BigQuery — use split_part() on PostgreSQL
        trim(split(directors, ',')[safe_offset(0)]) AS person_name,
        'director' AS person_role,
        rating
    FROM movies
    WHERE country IS NOT NULL
),

music_spine AS (
    SELECT
        country,
        'music' AS domain,
        album_id AS item_id,
        title AS item_title,
        artist AS person_name,
        'artist' AS person_role,
        rating
    FROM music
    WHERE country IS NOT NULL
),

manga_spine AS (
    SELECT
        country,
        'manga' AS domain,
        manga_id AS item_id,
        title AS item_title,
        author AS person_name,
        'author' AS person_role,
        rating
    FROM manga
    WHERE country IS NOT NULL
),

anime_spine AS (
    SELECT
        country,
        'anime' AS domain,
        anime_id AS item_id,
        title AS item_title,
        trim(split(directors, ',')[safe_offset(0)]) AS person_name,
        'director' AS person_role,
        rating
    FROM anime
    WHERE country IS NOT NULL
),

combined AS (
    SELECT * FROM books_spine
    UNION ALL
    SELECT * FROM movies_spine
    UNION ALL
    SELECT * FROM music_spine
    UNION ALL
    SELECT * FROM manga_spine
    UNION ALL
    SELECT * FROM anime_spine
)

SELECT
    c.*,
    iso.iso_alpha3
FROM combined AS c
LEFT JOIN iso_codes AS iso
    ON lower(trim(c.country)) = iso.country_key
