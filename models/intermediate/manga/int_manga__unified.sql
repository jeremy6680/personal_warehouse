-- ============================================================
-- Model: int_manga__unified
-- Layer: Intermediate
-- Description: Manga collection from BookBuddy rows where category = 'Manga'.
--              Genre is normalised via genre_mapping (domain = manga).
--              Manual ratings apply as a last-resort fallback.
--              Country is joined from manga_author_countries and translated
--              through country_name_fr.
-- Dependencies: stg_csv__bookbuddy, manga_author_countries, genre_mapping,
--               manual_ratings, country_name_fr
-- Adapter note: Standard SQL.
-- ============================================================

WITH

bookbuddy AS (
    SELECT * FROM {{ ref('stg_csv__bookbuddy') }}
),

manga_author_countries AS (
    SELECT
        country,
        lower(trim(author)) AS author_key
    FROM {{ ref('manga_author_countries') }}
),

genre_mapping AS (
    SELECT
        normalized_genre,
        lower(trim(raw_genre)) AS raw_genre_key
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'manga'
),

manual_ratings AS (
    SELECT
        rating AS manual_rating,
        lower(trim(title)) AS title_key,
        lower(trim(author_or_director_or_artist)) AS creator_key
    FROM {{ ref('manual_ratings') }}
    WHERE domain = 'manga'
),

country_name_fr AS (
    SELECT
        country_fr,
        lower(trim(country_en)) AS country_key
    FROM {{ ref('country_name_fr') }}
),

manga_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key,
        lower(trim(author)) AS author_key
    FROM bookbuddy
    WHERE category = 'Manga'
),

combined AS (
    SELECT
        book_id AS manga_id,
        title,
        author,
        gm.normalized_genre AS genre,
        category,
        isbn,
        tags,
        'bookbuddy' AS source,
        coalesce(nullif(rating, 0), mr.manual_rating) AS rating,
        coalesce(cnf.country_fr, mac.country) AS country
    FROM manga_keyed AS mk
    LEFT JOIN genre_mapping AS gm
        ON lower(trim(mk.genre)) = gm.raw_genre_key
    LEFT JOIN manga_author_countries AS mac
        ON mk.author_key = mac.author_key
    LEFT JOIN country_name_fr AS cnf
        ON lower(trim(mac.country)) = cnf.country_key
    LEFT JOIN manual_ratings AS mr
        ON
            mk.title_key = mr.title_key
            AND mk.author_key = mr.creator_key
)

SELECT * FROM combined
