-- ============================================================
-- Model: int_movies__unified
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
--              country uses a two-tier lookup:
--                1. director_countries seed on primary director (matched /
--                   moviebuddy_only rows, where director data is available)
--                2. film_countries seed on (title, release_year) for
--                   letterboxd_only rows, which carry no director data
--              Note: Letterboxd exports do not include TMDB IDs. TMDB-based
--              matching can be added if the export format is extended.
-- Dependencies: stg_csv__moviebuddy, stg_csv__letterboxd,
--               director_countries, film_countries
-- Adapter note: QUALIFY and SPLIT used — supported on BigQuery and DuckDB.
--               For PostgreSQL replace QUALIFY with ROW_NUMBER() subquery
--               and SPLIT(...)[SAFE_OFFSET(0)] with split_part(..., ',', 1).
-- ============================================================

WITH

moviebuddy AS (
    SELECT * FROM {{ ref('stg_csv__moviebuddy') }}
),

letterboxd AS (
    SELECT * FROM {{ ref('stg_csv__letterboxd') }}
),

director_countries AS (
    SELECT
        lower(trim(director)) AS director_key,
        country
    FROM {{ ref('director_countries') }}
),

film_countries AS (
    SELECT
        lower(trim(title))          AS title_key,
        CAST(release_year AS INT64) AS release_year,
        country
    FROM {{ ref('film_countries') }}
),

moviebuddy_keyed AS (
    SELECT
        *,
        lower(trim(title))                                             AS title_key,
        -- Primary director: first entry in comma-separated list
        -- Adapter note: SPLIT/SAFE_OFFSET is BigQuery/DuckDB — use split_part() on PostgreSQL
        lower(trim(SPLIT(directors, ',')[SAFE_OFFSET(0)]))             AS primary_director_key
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
        'title_year'          AS match_type,
        dc.country
    FROM title_year_matches      m
    INNER JOIN moviebuddy_keyed  mb ON m.mb_movie_id      = mb.movie_id
    INNER JOIN letterboxd_aggregated lb
        ON  m.lb_title_key    = lb.title_key
        AND m.lb_release_year = lb.release_year
    LEFT JOIN director_countries dc ON mb.primary_director_key = dc.director_key
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
        CAST(NULL AS STRING)  AS match_type,
        dc.country
    FROM moviebuddy_keyed mb
    LEFT JOIN title_year_matches m  ON mb.movie_id             = m.mb_movie_id
    LEFT JOIN director_countries dc ON mb.primary_director_key = dc.director_key
    WHERE m.mb_movie_id IS NULL
),

-- Case 3a: isolate Letterboxd-only rows and compute surrogate key before joining
-- film_countries — avoids release_year ambiguity in generate_surrogate_key.
letterboxd_only_base AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['film_name', 'release_year']) }} AS movie_id,
        lb.film_name,
        lb.release_year,
        lb.title_key,
        lb.first_watched_date,
        lb.last_watched_date,
        lb.watch_count,
        lb.letterboxd_rating,
        lb.letterboxd_uri
    FROM letterboxd_aggregated lb
    LEFT JOIN title_year_matches m
        ON  lb.title_key    = m.lb_title_key
        AND lb.release_year = m.lb_release_year
    WHERE m.lb_title_key IS NULL
),

-- Case 3: film in Letterboxd only (logged/loved but not in MovieBuddy collection)
letterboxd_only AS (
    SELECT
        lob.movie_id,
        lob.film_name         AS title,
        CAST(NULL AS STRING)  AS content_type,
        lob.release_year,
        CAST(NULL AS FLOAT64) AS rating,
        CAST(NULL AS STRING)  AS directors,
        CAST(NULL AS STRING)  AS genres,
        CAST(NULL AS INT64)   AS runtime_minutes,
        CAST(NULL AS INT64)   AS tmdb_id,
        lob.first_watched_date,
        lob.last_watched_date,
        lob.watch_count,
        lob.letterboxd_rating,
        lob.letterboxd_uri,
        CAST(NULL AS STRING)  AS match_type,
        fc.country
    FROM letterboxd_only_base lob
    LEFT JOIN film_countries fc
        ON  lob.title_key    = fc.title_key
        AND lob.release_year = fc.release_year
),

combined AS (
    SELECT * FROM matched
    UNION ALL
    SELECT * FROM moviebuddy_only
    UNION ALL
    SELECT * FROM letterboxd_only
)

SELECT * FROM combined
