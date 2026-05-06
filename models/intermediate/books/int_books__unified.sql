-- ============================================================
-- Model: int_books__unified
-- Layer: Intermediate
-- Description: Full union of BookBuddy and Goodreads, deduplicated.
--              Matching is attempted first on ISBN, then on normalized
--              title + author. Three output cases:
--                - matched: one row per book with columns from both sources
--                - bookbuddy_only: in BookBuddy but not found in Goodreads
--                - goodreads_only: in Goodreads but not found in BookBuddy
--              Genre is normalised via the genre_mapping seed (ADR-022).
--              Author names are normalised via the author_name_mapping seed
--              before cross-source matching (ADR-023).
--              country is joined from the author_countries seed on normalised author.
-- Dependencies: stg_csv__bookbuddy, stg_csv__goodreads,
--               author_countries, genre_mapping, author_name_mapping
-- Adapter note: Works on BigQuery, DuckDB, and PostgreSQL.
--               No QUALIFY — dedup handled via NOT IN subqueries.
-- ============================================================

WITH

bookbuddy AS (
    SELECT * FROM {{ ref('stg_csv__bookbuddy') }}
),

goodreads AS (
    SELECT * FROM {{ ref('stg_csv__goodreads') }}
),

author_countries AS (
    SELECT
        lower(trim(author)) AS author_key,
        country
    FROM {{ ref('author_countries') }}
),

-- Author name normalisation: variants → canonical name (ADR-023)
author_name_mapping AS (
    SELECT
        lower(trim(raw_name))       AS raw_author_key,
        lower(trim(canonical_name)) AS canonical_author_key
    FROM {{ ref('author_name_mapping') }}
),

-- Genre normalisation: raw values → French labels (ADR-022)
-- domain = 'books'; rows with empty normalized_genre are parasitic tags
genre_mapping AS (
    SELECT
        lower(trim(raw_genre))  AS raw_genre_key,
        normalized_genre
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'books'
),

bookbuddy_keyed AS (
    SELECT
        *,
        lower(trim(title))  AS title_key,
        lower(trim(author)) AS raw_author_key
    FROM bookbuddy
),

-- Apply author name normalisation to BookBuddy rows
bookbuddy_normalised AS (
    SELECT
        bb.*,
        COALESCE(anm.canonical_author_key, bb.raw_author_key) AS author_key
    FROM bookbuddy_keyed bb
    LEFT JOIN author_name_mapping anm
        ON bb.raw_author_key = anm.raw_author_key
),

goodreads_keyed AS (
    SELECT
        *,
        {{ dbt_utils.generate_surrogate_key(['title', 'author']) }} AS surrogate_id,
        lower(trim(title))  AS title_key,
        lower(trim(author)) AS raw_author_key
    FROM goodreads
),

-- Apply author name normalisation to Goodreads rows
goodreads_normalised AS (
    SELECT
        gr.*,
        COALESCE(anm.canonical_author_key, gr.raw_author_key) AS author_key
    FROM goodreads_keyed gr
    LEFT JOIN author_name_mapping anm
        ON gr.raw_author_key = anm.raw_author_key
),

-- Pass 1: match on ISBN where both sides carry a non-null ISBN
isbn_matches AS (
    SELECT
        bb.book_id AS bb_book_id,
        gr.book_id AS gr_book_id,
        'isbn'     AS match_type
    FROM bookbuddy_normalised bb
    INNER JOIN goodreads_normalised gr
        ON  bb.isbn IS NOT NULL
        AND gr.isbn IS NOT NULL
        AND bb.isbn = gr.isbn
),

-- Pass 2: fall back to normalised title + normalised author
title_author_matches AS (
    SELECT
        bb.book_id     AS bb_book_id,
        gr.book_id     AS gr_book_id,
        'title_author' AS match_type
    FROM bookbuddy_normalised bb
    INNER JOIN goodreads_normalised gr
        ON  bb.title_key  = gr.title_key
        AND bb.author_key = gr.author_key
    WHERE bb.book_id NOT IN (SELECT bb_book_id FROM isbn_matches)
      AND gr.book_id NOT IN (SELECT gr_book_id FROM isbn_matches)
),

all_matches AS (
    SELECT * FROM isbn_matches
    UNION ALL
    SELECT * FROM title_author_matches
),

-- Case 1: book present in both sources
matched AS (
    SELECT
        bb.book_id,
        bb.title,
        bb.author,
        gm.normalized_genre                               AS genre,
        bb.category,
        bb.rating,
        bb.isbn,
        bb.tags,
        gr.book_id                                        AS goodreads_id,
        gr.year_published,
        gr.publisher,
        gr.rating                                         AS goodreads_rating,
        m.match_type,
        ac.country
    FROM all_matches m
    INNER JOIN bookbuddy_normalised bb  ON m.bb_book_id = bb.book_id
    INNER JOIN goodreads_normalised gr  ON m.gr_book_id = gr.book_id
    LEFT JOIN genre_mapping gm          ON lower(trim(bb.genre)) = gm.raw_genre_key
    LEFT JOIN author_countries ac       ON bb.author_key = ac.author_key
),

-- Case 2: book in BookBuddy only
bookbuddy_only AS (
    SELECT
        bb.book_id,
        bb.title,
        bb.author,
        gm.normalized_genre                               AS genre,
        bb.category,
        bb.rating,
        bb.isbn,
        bb.tags,
        CAST(NULL AS STRING)                              AS goodreads_id,
        CAST(NULL AS INT64)                               AS year_published,
        CAST(NULL AS STRING)                              AS publisher,
        CAST(NULL AS INT64)                               AS goodreads_rating,
        CAST(NULL AS STRING)                              AS match_type,
        ac.country
    FROM bookbuddy_normalised bb
    LEFT JOIN genre_mapping gm    ON lower(trim(bb.genre)) = gm.raw_genre_key
    LEFT JOIN author_countries ac ON bb.author_key = ac.author_key
    WHERE bb.book_id NOT IN (SELECT bb_book_id FROM all_matches)
),

-- Case 3: book in Goodreads only
goodreads_only AS (
    SELECT
        gr.surrogate_id                                   AS book_id,
        gr.title,
        gr.author,
        CAST(NULL AS STRING)                              AS genre,
        CAST(NULL AS STRING)                              AS category,
        CAST(NULL AS FLOAT64)                             AS rating,
        gr.isbn,
        CAST(NULL AS STRING)                              AS tags,
        gr.book_id                                        AS goodreads_id,
        gr.year_published,
        gr.publisher,
        gr.rating                                         AS goodreads_rating,
        CAST(NULL AS STRING)                              AS match_type,
        ac.country
    FROM goodreads_normalised gr
    LEFT JOIN author_countries ac ON gr.author_key = ac.author_key
    WHERE gr.book_id NOT IN (SELECT gr_book_id FROM all_matches)
),

combined AS (
    SELECT * FROM matched
    UNION ALL
    SELECT * FROM bookbuddy_only
    UNION ALL
    SELECT * FROM goodreads_only
)

SELECT * FROM combined