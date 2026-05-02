-- ============================================================
-- Model: mrt_books__collection
-- Layer: Mart
-- Description: Full book collection — all statuses (read, unread, reading, DNF).
--              Single unified rating: Goodreads is the source of truth when both
--              sources have a rating, otherwise BookBuddy rating is used.
--              source indicates which app(s) contributed the row.
-- Dependencies: int_books__unified
-- Adapter note: Standard SQL — works on BigQuery, DuckDB, and PostgreSQL.
-- ============================================================

{{ config(
    materialized='table',
    tags=['mart', 'books']
) }}

WITH

source_data AS (
    SELECT * FROM {{ ref('int_books__unified') }}
),

collection AS (
    SELECT
        book_id,
        title,
        author,
        genre,
        category,
        status,
        CASE WHEN status = 'Read' THEN TRUE ELSE FALSE END          AS is_read,
        -- Goodreads is source of truth for rating; fall back to BookBuddy (0 = unrated)
        COALESCE(
            CAST(goodreads_rating AS FLOAT64),
            NULLIF(rating, 0)
        )                                                           AS rating,
        year_published,
        publisher,
        isbn,
        tags,
        country,
        CASE
            WHEN match_type IS NOT NULL   THEN 'bookbuddy_and_goodreads'
            WHEN goodreads_id IS NOT NULL THEN 'goodreads'
            ELSE                               'bookbuddy'
        END                                                         AS source,
        goodreads_id
    FROM source_data
),

with_flags AS (
    SELECT
        *,
        rating IS NOT NULL                                          AS is_rated
    FROM collection
)

SELECT * FROM with_flags
