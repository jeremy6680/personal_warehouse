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
        lower(trim(author)) AS author_key,
        country
    FROM {{ ref('manga_author_countries') }}
),

genre_mapping AS (
    SELECT
        lower(trim(raw_genre)) AS raw_genre_key,
        normalized_genre
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'manga'
),

manual_ratings AS (
    SELECT
        lower(trim(title))                        AS title_key,
        lower(trim(author_or_director_or_artist)) AS creator_key,
        rating                                    AS manual_rating
    FROM {{ ref('manual_ratings') }}
    WHERE domain = 'manga'
),

country_name_fr AS (
    SELECT
        lower(trim(country_en)) AS country_key,
        country_fr
    FROM {{ ref('country_name_fr') }}
),

manga_keyed AS (
    SELECT
        *,
        lower(trim(title))  AS title_key,
        lower(trim(author)) AS author_key
    FROM bookbuddy
    WHERE category = 'Manga'
),

combined AS (
    SELECT
        book_id                                                   AS manga_id,
        title,
        author,
        gm.normalized_genre                                       AS genre,
        category,
        COALESCE(NULLIF(rating, 0), mr.manual_rating)             AS rating,
        isbn,
        tags,
        COALESCE(cnf.country_fr, mac.country)                     AS country,
        'bookbuddy'                                               AS source
    FROM manga_keyed mk
    LEFT JOIN genre_mapping gm
        ON lower(trim(mk.genre)) = gm.raw_genre_key
    LEFT JOIN manga_author_countries mac
        ON mk.author_key = mac.author_key
    LEFT JOIN country_name_fr cnf
        ON lower(trim(mac.country)) = cnf.country_key
    LEFT JOIN manual_ratings mr
        ON  mk.title_key  = mr.title_key
        AND mk.author_key = mr.creator_key
)

SELECT * FROM combined
