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
--              Anime excluded — handled in int_anime__unified (ADR-017).
--              Genre is normalised to French via the genre_mapping seed (ADR-022).
--              Manual ratings applied as last-resort fallback (ADR-024).
--              Country name translated to French via country_name_fr (ADR-026).
--              country uses a two-tier lookup:
--                1. director_countries seed on primary director (matched /
--                   moviebuddy_only rows, where director data is available)
--                2. film_countries seed on (title, release_year) for
--                   letterboxd_only rows, which carry no director data
--              Note: Letterboxd exports do not include TMDB IDs. TMDB-based
--              matching can be added if the export format is extended.
-- Dependencies: stg_csv__moviebuddy, stg_csv__letterboxd,
--               director_countries, film_countries, genre_mapping,
--               manual_ratings, country_name_fr
-- Adapter note: QUALIFY and SPLIT used — supported on BigQuery and DuckDB.
--               For PostgreSQL replace QUALIFY with ROW_NUMBER() subquery
--               and SPLIT(...)[SAFE_OFFSET(0)] with split_part(..., ',', 1).
--               Genre normalisation uses UNNEST — BigQuery and DuckDB only.
--               For PostgreSQL, apply normalisation at the mart layer instead.
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

-- Genre normalisation: raw values → French labels (ADR-022)
-- domain = 'movies'; rows with null normalized_genre are parasitic tags
genre_mapping AS (
    SELECT
        lower(trim(raw_genre)) AS raw_genre_key,
        normalized_genre
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'movies'
),

-- Manual ratings fallback: items with no source rating (ADR-024)
-- domain = 'movies'; join key is lower(trim(title)) + lower(trim(creator))
manual_ratings AS (
    SELECT
        lower(trim(title))                        AS title_key,
        lower(trim(author_or_director_or_artist)) AS creator_key,
        rating                                    AS manual_rating
    FROM {{ ref('manual_ratings') }}
    WHERE domain = 'movies'
),

-- Country name French translation (ADR-026)
country_name_fr AS (
    SELECT
        lower(trim(country_en)) AS country_key,
        country_fr
    FROM {{ ref('country_name_fr') }}
),

-- Exclude anime — handled in int_anime__unified (ADR-017)
-- Anime = TV Shows with Animation in genres
moviebuddy_keyed AS (
    SELECT
        *,
        lower(trim(title))                                             AS title_key,
        -- Primary director: first entry in comma-separated list
        -- Adapter note: SPLIT/SAFE_OFFSET is BigQuery/DuckDB — use split_part() on PostgreSQL
        lower(trim(SPLIT(directors, ',')[SAFE_OFFSET(0)]))             AS primary_director_key
    FROM moviebuddy
    WHERE NOT (
        content_type = 'TV Show'
        AND LOWER(genres) LIKE '%animation%'
    )
),

-- Normalise genres: split comma-separated string, join each token to
-- genre_mapping, re-aggregate to a normalised comma-separated string.
-- Adapter note: UNNEST(SPLIT(...)) is BigQuery and DuckDB only.
-- For PostgreSQL, move this normalisation to the mart layer.
moviebuddy_genres_normalised AS (
    SELECT
        movie_id,
        STRING_AGG(
            gm.normalized_genre
            ORDER BY gm.normalized_genre
        ) AS genres_fr
    FROM moviebuddy_keyed mb,
        UNNEST(SPLIT(mb.genres, ',')) AS raw_genre
    LEFT JOIN genre_mapping gm
        ON lower(trim(raw_genre)) = gm.raw_genre_key
    WHERE gm.normalized_genre IS NOT NULL
    GROUP BY movie_id
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
        COALESCE(mb.rating, mr.manual_rating)        AS rating,
        mb.directors,
        gn.genres_fr                                 AS genres,
        mb.runtime_minutes,
        mb.tmdb_id,
        lb.first_watched_date,
        lb.last_watched_date,
        lb.watch_count,
        lb.letterboxd_rating,
        lb.letterboxd_uri,
        'title_year'                                 AS match_type,
        COALESCE(cnf.country_fr, dc.country)         AS country
    FROM title_year_matches          m
    INNER JOIN moviebuddy_keyed      mb ON m.mb_movie_id      = mb.movie_id
    INNER JOIN letterboxd_aggregated lb
        ON  m.lb_title_key    = lb.title_key
        AND m.lb_release_year = lb.release_year
    LEFT JOIN moviebuddy_genres_normalised gn ON mb.movie_id = gn.movie_id
    LEFT JOIN director_countries dc ON mb.primary_director_key = dc.director_key
    LEFT JOIN country_name_fr cnf   ON lower(trim(dc.country)) = cnf.country_key
    LEFT JOIN manual_ratings mr
        ON  mb.title_key           = mr.title_key
        AND mb.primary_director_key = mr.creator_key
),

-- Case 2: film in MovieBuddy only
moviebuddy_only AS (
    SELECT
        mb.movie_id,
        mb.title,
        mb.content_type,
        mb.release_year,
        COALESCE(mb.rating, mr.manual_rating)        AS rating,
        mb.directors,
        gn.genres_fr                                 AS genres,
        mb.runtime_minutes,
        mb.tmdb_id,
        CAST(NULL AS DATE)                           AS first_watched_date,
        CAST(NULL AS DATE)                           AS last_watched_date,
        CAST(NULL AS INT64)                          AS watch_count,
        CAST(NULL AS FLOAT64)                        AS letterboxd_rating,
        CAST(NULL AS STRING)                         AS letterboxd_uri,
        CAST(NULL AS STRING)                         AS match_type,
        COALESCE(cnf.country_fr, dc.country)         AS country
    FROM moviebuddy_keyed mb
    LEFT JOIN title_year_matches m      ON mb.movie_id              = m.mb_movie_id
    LEFT JOIN moviebuddy_genres_normalised gn ON mb.movie_id        = gn.movie_id
    LEFT JOIN director_countries dc     ON mb.primary_director_key  = dc.director_key
    LEFT JOIN country_name_fr cnf       ON lower(trim(dc.country))  = cnf.country_key
    LEFT JOIN manual_ratings mr
        ON  mb.title_key            = mr.title_key
        AND mb.primary_director_key = mr.creator_key
    WHERE m.mb_movie_id IS NULL
),

-- Case 3a: isolate Letterboxd-only rows before joining film_countries
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

-- Case 3: film in Letterboxd only
-- No director data available — country from film_countries seed only
letterboxd_only AS (
    SELECT
        lob.movie_id,
        lob.film_name                                AS title,
        CAST(NULL AS STRING)                         AS content_type,
        lob.release_year,
        COALESCE(
            CAST(NULL AS FLOAT64),
            mr.manual_rating
        )                                            AS rating,
        CAST(NULL AS STRING)                         AS directors,
        CAST(NULL AS STRING)                         AS genres,
        CAST(NULL AS INT64)                          AS runtime_minutes,
        CAST(NULL AS INT64)                          AS tmdb_id,
        lob.first_watched_date,
        lob.last_watched_date,
        lob.watch_count,
        lob.letterboxd_rating,
        lob.letterboxd_uri,
        CAST(NULL AS STRING)                         AS match_type,
        COALESCE(cnf.country_fr, fc.country)         AS country
    FROM letterboxd_only_base lob
    LEFT JOIN film_countries fc
        ON  lob.title_key    = fc.title_key
        AND lob.release_year = fc.release_year
    LEFT JOIN country_name_fr cnf ON lower(trim(fc.country)) = cnf.country_key
    LEFT JOIN manual_ratings mr
        ON  lob.title_key = mr.title_key
        AND mr.creator_key IS NULL  -- letterboxd-only rows have no director
),

combined AS (
    SELECT * FROM matched
    UNION ALL
    SELECT * FROM moviebuddy_only
    UNION ALL
    SELECT * FROM letterboxd_only
)

SELECT * FROM combined