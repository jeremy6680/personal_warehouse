-- ============================================================
-- Model: int_movies__unified
-- Layer: Intermediate
-- Description: Full union of MovieBuddy, Letterboxd, and Trakt movies,
--              deduplicated to one row per film. Matching is on normalized
--              title + release_year. Trakt and Letterboxd watched history is
--              aggregated before matching. Anime excluded — handled in
--              int_anime__unified (ADR-017). Rating priority follows ADR-019:
--              Trakt > Letterboxd > MovieBuddy > manual fallback.
-- Dependencies: stg_csv__moviebuddy, stg_csv__letterboxd,
--               stg_trakt__watched_movies, stg_trakt__ratings,
--               director_countries, film_countries, genre_mapping,
--               manual_ratings, country_name_fr
-- Adapter note: BigQuery-focused SQL (SAFE_CAST, SAFE_OFFSET, JSON functions).
-- ============================================================

WITH

moviebuddy AS (
    SELECT * FROM {{ ref('stg_csv__moviebuddy') }}
),

letterboxd AS (
    SELECT * FROM {{ ref('stg_csv__letterboxd') }}
),

trakt_watched_movies AS (
    SELECT * FROM {{ ref('stg_trakt__watched_movies') }}
),

trakt_ratings AS (
    SELECT * FROM {{ ref('stg_trakt__ratings') }}
    WHERE media_type = 'movie'
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

genre_mapping AS (
    SELECT
        lower(trim(raw_genre)) AS raw_genre_key,
        normalized_genre
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'movies'
),

manual_ratings AS (
    SELECT
        lower(trim(title))                        AS title_key,
        lower(trim(author_or_director_or_artist)) AS creator_key,
        rating                                    AS manual_rating
    FROM {{ ref('manual_ratings') }}
    WHERE domain = 'movies'
),

country_name_fr AS (
    SELECT
        lower(trim(country_en)) AS country_key,
        country_fr
    FROM {{ ref('country_name_fr') }}
),

moviebuddy_keyed AS (
    SELECT
        *,
        lower(trim(title))                                 AS title_key,
        lower(trim(SPLIT(directors, ',')[SAFE_OFFSET(0)])) AS primary_director_key
    FROM moviebuddy
    WHERE NOT (
        content_type = 'TV Show'
        AND LOWER(genres) LIKE '%animation%'
    )
),

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

letterboxd_aggregated AS (
    SELECT
        title_key,
        film_name,
        release_year,
        min(watched_date) OVER (PARTITION BY title_key, release_year) AS first_watched_date,
        watched_date                                                  AS last_watched_date,
        count(*) OVER (PARTITION BY title_key, release_year)          AS watch_count,
        rating                                                        AS letterboxd_rating,
        letterboxd_uri
    FROM letterboxd_keyed
    QUALIFY
        row_number() OVER (
            PARTITION BY title_key, release_year
            ORDER BY watched_date DESC
        ) = 1
),

trakt_watched_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM trakt_watched_movies
),

trakt_ratings_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM trakt_ratings
    QUALIFY
        row_number() OVER (
            PARTITION BY lower(trim(title)), release_year
            ORDER BY rated_at DESC
        ) = 1
),

trakt_movies AS (
    SELECT
        COALESCE(tw.title_key, tr.title_key)          AS title_key,
        COALESCE(tw.title, tr.title)                  AS title,
        COALESCE(tw.release_year, tr.release_year)    AS release_year,
        COALESCE(tw.trakt_movie_id, tr.trakt_id)      AS trakt_movie_id,
        COALESCE(tw.slug, tr.slug)                    AS trakt_slug,
        COALESCE(tw.imdb_id, tr.imdb_id)              AS trakt_imdb_id,
        COALESCE(tw.tmdb_id, tr.tmdb_id)              AS trakt_tmdb_id,
        tw.last_watched_at,
        tw.watch_count,
        tr.rating                                     AS trakt_rating,
        tr.rating_raw                                 AS trakt_rating_raw,
        tr.rated_at                                   AS trakt_rated_at,
        COALESCE(tw.genres, tr.genres)                AS genres,
        COALESCE(tw.runtime_minutes, tr.runtime_minutes) AS runtime_minutes,
        COALESCE(tw.country, tr.country)              AS country
    FROM trakt_watched_keyed tw
    FULL OUTER JOIN trakt_ratings_keyed tr
        ON  tw.title_key    = tr.title_key
        AND tw.release_year = tr.release_year
),

trakt_genres_normalised AS (
    SELECT
        title_key,
        release_year,
        STRING_AGG(
            gm.normalized_genre
            ORDER BY gm.normalized_genre
        ) AS genres_fr
    FROM trakt_movies tm,
        UNNEST(JSON_EXTRACT_ARRAY(tm.genres)) AS raw_genre_json
    LEFT JOIN genre_mapping gm
        ON lower(trim(JSON_VALUE(raw_genre_json))) = gm.raw_genre_key
    WHERE gm.normalized_genre IS NOT NULL
    GROUP BY title_key, release_year
),

title_year_unified AS (
    SELECT
        COALESCE(mb.title_key, lb.title_key, tm.title_key)             AS title_key,
        COALESCE(mb.release_year, lb.release_year, tm.release_year)    AS release_year,
        mb.movie_id                                                    AS moviebuddy_movie_id,
        lb.title_key IS NOT NULL                                       AS has_letterboxd,
        tm.title_key IS NOT NULL                                       AS has_trakt,
        mb.title_key IS NOT NULL                                       AS has_moviebuddy,
        mb.title                                                       AS moviebuddy_title,
        lb.film_name                                                   AS letterboxd_title,
        tm.title                                                       AS trakt_title,
        mb.content_type,
        mb.rating                                                      AS moviebuddy_rating,
        mb.directors,
        mb.primary_director_key,
        mb.runtime_minutes                                             AS moviebuddy_runtime_minutes,
        mb.tmdb_id                                                     AS moviebuddy_tmdb_id,
        lb.first_watched_date                                          AS letterboxd_first_watched_date,
        lb.last_watched_date                                           AS letterboxd_last_watched_date,
        lb.watch_count                                                 AS letterboxd_watch_count,
        lb.letterboxd_rating,
        lb.letterboxd_uri,
        tm.trakt_movie_id,
        tm.trakt_slug,
        tm.trakt_imdb_id,
        tm.trakt_tmdb_id,
        tm.last_watched_at                                             AS trakt_last_watched_at,
        tm.watch_count                                                 AS trakt_watch_count,
        tm.trakt_rating,
        tm.trakt_rating_raw,
        tm.trakt_rated_at,
        tm.runtime_minutes                                             AS trakt_runtime_minutes,
        tm.country                                                     AS trakt_country
    FROM moviebuddy_keyed mb
    FULL OUTER JOIN letterboxd_aggregated lb
        ON  mb.title_key    = lb.title_key
        AND mb.release_year = lb.release_year
    FULL OUTER JOIN trakt_movies tm
        ON  COALESCE(mb.title_key, lb.title_key)       = tm.title_key
        AND COALESCE(mb.release_year, lb.release_year) = tm.release_year
),

source_resolved AS (
    SELECT
        *,
        CASE
            WHEN has_trakt AND has_letterboxd AND has_moviebuddy THEN 'trakt_and_letterboxd_and_moviebuddy'
            WHEN has_trakt AND has_letterboxd THEN 'trakt_and_letterboxd'
            WHEN has_trakt AND has_moviebuddy THEN 'trakt_and_moviebuddy'
            WHEN has_letterboxd AND has_moviebuddy THEN 'letterboxd_and_moviebuddy'
            WHEN has_trakt THEN 'trakt'
            WHEN has_letterboxd THEN 'letterboxd'
            ELSE 'moviebuddy'
        END AS source
    FROM title_year_unified
),

combined AS (
    SELECT
        COALESCE(moviebuddy_title, trakt_title, letterboxd_title) AS title,
        content_type,
        sr.release_year,
        COALESCE(
            trakt_rating,
            letterboxd_rating,
            NULLIF(moviebuddy_rating, 0),
            mr.manual_rating
        )                                                        AS rating,
        directors,
        COALESCE(mgn.genres_fr, tgn.genres_fr)                  AS genres,
        COALESCE(moviebuddy_runtime_minutes, trakt_runtime_minutes) AS runtime_minutes,
        COALESCE(moviebuddy_tmdb_id, trakt_tmdb_id)              AS tmdb_id,
        CASE
            WHEN letterboxd_first_watched_date IS NOT NULL THEN letterboxd_first_watched_date
            WHEN trakt_last_watched_at IS NOT NULL THEN DATE(trakt_last_watched_at)
        END                                                      AS first_watched_date,
        CASE
            WHEN letterboxd_last_watched_date IS NULL THEN DATE(trakt_last_watched_at)
            WHEN trakt_last_watched_at IS NULL THEN letterboxd_last_watched_date
            ELSE GREATEST(letterboxd_last_watched_date, DATE(trakt_last_watched_at))
        END                                                      AS last_watched_date,
        COALESCE(letterboxd_watch_count, 0) + COALESCE(trakt_watch_count, 0) AS watch_count,
        trakt_rating,
        trakt_rating_raw,
        trakt_rated_at,
        trakt_movie_id,
        trakt_slug,
        trakt_imdb_id,
        letterboxd_rating,
        letterboxd_uri,
        CASE
            WHEN source IN (
                'trakt_and_letterboxd_and_moviebuddy',
                'trakt_and_letterboxd',
                'trakt_and_moviebuddy',
                'letterboxd_and_moviebuddy'
            ) THEN 'title_year'
        END                                                      AS match_type,
        COALESCE(cnf_director.country_fr, cnf_film.country_fr, dc.country, fc.country, trakt_country) AS country,
        source
    FROM source_resolved sr
    LEFT JOIN moviebuddy_genres_normalised mgn
        ON sr.moviebuddy_movie_id = mgn.movie_id
    LEFT JOIN trakt_genres_normalised tgn
        ON  sr.title_key    = tgn.title_key
        AND sr.release_year = tgn.release_year
    LEFT JOIN director_countries dc
        ON sr.primary_director_key = dc.director_key
    LEFT JOIN country_name_fr cnf_director
        ON lower(trim(dc.country)) = cnf_director.country_key
    LEFT JOIN film_countries fc
        ON  sr.title_key    = fc.title_key
        AND sr.release_year = fc.release_year
    LEFT JOIN country_name_fr cnf_film
        ON lower(trim(fc.country)) = cnf_film.country_key
    LEFT JOIN manual_ratings mr
        ON  sr.title_key = mr.title_key
        AND (
            sr.primary_director_key = mr.creator_key
            OR (sr.primary_director_key IS NULL AND mr.creator_key IS NULL)
        )
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['title', 'release_year']) }} AS movie_id,
    *
FROM combined
