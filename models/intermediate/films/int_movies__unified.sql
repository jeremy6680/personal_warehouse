-- ============================================================
-- Model: int_movies__collection_with_diary
-- Layer: Intermediate
-- Description: Full union of MovieBuddy and Letterboxd, deduplicated to one
--              row per film. Three output cases:
--                - matched: one row with columns from both sources
--                - moviebuddy_only: in collection but not logged on Letterboxd
--                - letterboxd_only: logged on Letterboxd but not in collection
--              Letterboxd diary is aggregated before matching — multiple entries
--              for the same film (rewatches) are collapsed to one row; the most
--              recent entry wins for rating and URI, counts and date bounds span
--              all entries. Matching is on normalized title + release_year.
--              Note: Letterboxd exports do not include TMDB IDs. TMDB-based
--              matching can be added if the export format is extended.
-- Dependencies: stg_csv__moviebuddy, stg_csv__letterboxd
-- Adapter note: QUALIFY used — supported on BigQuery and DuckDB.
--               For PostgreSQL replace with a ROW_NUMBER() subquery.
-- ============================================================

WITH

moviebuddy AS (
    SELECT * FROM {{ ref('stg_csv__moviebuddy') }}
),

letterboxd AS (
    SELECT * FROM {{ ref('stg_csv__letterboxd') }}
),

moviebuddy_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM moviebuddy
),

letterboxd_keyed AS (
    SELECT
        *,
        lower(trim(film_name)) AS title_key
    FROM letterboxd
),

-- Collapse multiple diary entries per film to one row.
-- Window functions compute aggregates before QUALIFY deduplicates to the most
-- recent entry, so watch_count reflects all diary entries for that film.
letterboxd_aggregated AS (
    SELECT
        title_key,
        film_name,
        release_year,
        min(watched_date) OVER (PARTITION BY title_key, release_year) AS first_watched_date,
        watched_date                                                   AS last_watched_date,
        count(*) OVER (PARTITION BY title_key, release_year)          AS watch_count,
        rating                                                         AS letterboxd_rating,
        letterboxd_uri
    FROM letterboxd_keyed
    QUALIFY
        row_number() OVER (
            PARTITION BY title_key, release_year
            ORDER BY watched_date DESC
        ) = 1
),

-- Single-pass match on normalized title + release_year
title_year_matches AS (
    SELECT
        mb.movie_id        AS mb_movie_id,
        lb.title_key       AS lb_title_key,
        lb.release_year    AS lb_release_year
    FROM moviebuddy_keyed        mb
    INNER JOIN letterboxd_aggregated lb
        ON  mb.title_key    = lb.title_key
        AND mb.release_year = lb.release_year
),

-- Case 1: film present in both sources
matched AS (
    SELECT
        mb.movie_id,
        mb.title,
        mb.content_type,
        mb.release_year,
        mb.rating,
        mb.directors,
        mb.genres,
        mb.runtime_minutes,
        mb.tmdb_id,
        lb.first_watched_date,
        lb.last_watched_date,
        lb.watch_count,
        lb.letterboxd_rating,
        lb.letterboxd_uri,
        'title_year'          AS match_type
    FROM title_year_matches      m
    INNER JOIN moviebuddy_keyed  mb ON m.mb_movie_id      = mb.movie_id
    INNER JOIN letterboxd_aggregated lb
        ON  m.lb_title_key    = lb.title_key
        AND m.lb_release_year = lb.release_year
),

-- Case 2: film in MovieBuddy only (in collection but never logged on Letterboxd)
moviebuddy_only AS (
    SELECT
        mb.movie_id,
        mb.title,
        mb.content_type,
        mb.release_year,
        mb.rating,
        mb.directors,
        mb.genres,
        mb.runtime_minutes,
        mb.tmdb_id,
        CAST(NULL AS DATE)    AS first_watched_date,
        CAST(NULL AS DATE)    AS last_watched_date,
        CAST(NULL AS INT64)   AS watch_count,
        CAST(NULL AS FLOAT64) AS letterboxd_rating,
        CAST(NULL AS STRING)  AS letterboxd_uri,
        CAST(NULL AS STRING)  AS match_type
    FROM moviebuddy_keyed mb
    LEFT JOIN title_year_matches m ON mb.movie_id = m.mb_movie_id
    WHERE m.mb_movie_id IS NULL
),

-- Case 3: film in Letterboxd only (logged/loved but not in MovieBuddy collection)
letterboxd_only AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['film_name', 'release_year']) }} AS movie_id,
        lb.film_name          AS title,
        CAST(NULL AS STRING)  AS content_type,
        lb.release_year,
        CAST(NULL AS FLOAT64) AS rating,
        CAST(NULL AS STRING)  AS directors,
        CAST(NULL AS STRING)  AS genres,
        CAST(NULL AS INT64)   AS runtime_minutes,
        CAST(NULL AS INT64)   AS tmdb_id,
        lb.first_watched_date,
        lb.last_watched_date,
        lb.watch_count,
        lb.letterboxd_rating,
        lb.letterboxd_uri,
        CAST(NULL AS STRING)  AS match_type
    FROM letterboxd_aggregated lb
    LEFT JOIN title_year_matches m
        ON  lb.title_key    = m.lb_title_key
        AND lb.release_year = m.lb_release_year
    WHERE m.lb_title_key IS NULL
),

combined AS (
    SELECT * FROM matched
    UNION ALL
    SELECT * FROM moviebuddy_only
    UNION ALL
    SELECT * FROM letterboxd_only
)

SELECT * FROM combined
