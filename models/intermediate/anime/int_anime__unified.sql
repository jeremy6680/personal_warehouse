-- ============================================================
-- Model: int_anime__unified
-- Layer: Intermediate
-- Description: Anime union from MovieBuddy animated TV shows and Trakt watched
--              or rated shows. Matching is on normalized title + release_year.
--              Rating priority follows ADR-019: Trakt > MovieBuddy > manual.
-- Dependencies: stg_csv__moviebuddy, stg_trakt__watched_shows,
--               stg_trakt__ratings, anime_director_countries,
--               genre_mapping, manual_ratings, country_name_fr
-- Adapter note: BigQuery-focused SQL (SAFE_CAST, SAFE_OFFSET, JSON functions).
-- ============================================================

WITH

moviebuddy AS (
    SELECT * FROM {{ ref('stg_csv__moviebuddy') }}
),

trakt_watched_shows AS (
    SELECT * FROM {{ ref('stg_trakt__watched_shows') }}
),

trakt_ratings AS (
    SELECT * FROM {{ ref('stg_trakt__ratings') }}
    WHERE media_type = 'show'
),

genre_mapping AS (
    SELECT
        lower(trim(raw_genre)) AS raw_genre_key,
        normalized_genre
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'movies'
),

anime_director_countries AS (
    SELECT
        lower(trim(director)) AS director_key,
        country
    FROM {{ ref('anime_director_countries') }}
),

manual_ratings AS (
    SELECT
        lower(trim(title)) AS title_key,
        rating             AS manual_rating
    FROM {{ ref('manual_ratings') }}
    WHERE domain = 'anime'
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
        lower(trim(title)) AS title_key
    FROM moviebuddy
    WHERE content_type = 'TV Show'
      AND LOWER(genres) LIKE '%animation%'
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

trakt_watched_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM trakt_watched_shows
    WHERE LOWER(genres) LIKE '%animation%'
       OR LOWER(genres) LIKE '%anime%'
),

trakt_ratings_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM trakt_ratings
    WHERE LOWER(genres) LIKE '%animation%'
       OR LOWER(genres) LIKE '%anime%'
    QUALIFY
        row_number() OVER (
            PARTITION BY lower(trim(title)), release_year
            ORDER BY rated_at DESC
        ) = 1
),

trakt_shows AS (
    SELECT
        COALESCE(tw.title_key, tr.title_key)          AS title_key,
        COALESCE(tw.title, tr.title)                  AS title,
        COALESCE(tw.release_year, tr.release_year)    AS release_year,
        COALESCE(tw.trakt_show_id, tr.trakt_id)       AS trakt_show_id,
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
        tw.status,
        tw.network,
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
    FROM trakt_shows ts,
        UNNEST(JSON_EXTRACT_ARRAY(ts.genres)) AS raw_genre_json
    LEFT JOIN genre_mapping gm
        ON lower(trim(JSON_VALUE(raw_genre_json))) = gm.raw_genre_key
    WHERE gm.normalized_genre IS NOT NULL
    GROUP BY title_key, release_year
),

title_year_unified AS (
    SELECT
        COALESCE(mb.title_key, ts.title_key)          AS title_key,
        COALESCE(mb.release_year, ts.release_year)    AS release_year,
        mb.movie_id                                   AS moviebuddy_movie_id,
        mb.title                                      AS moviebuddy_title,
        ts.title                                      AS trakt_title,
        mb.rating                                     AS moviebuddy_rating,
        mb.directors,
        mb.runtime_minutes                            AS moviebuddy_runtime_minutes,
        mb.tmdb_id                                    AS moviebuddy_tmdb_id,
        ts.trakt_show_id,
        ts.trakt_slug,
        ts.trakt_imdb_id,
        ts.trakt_tmdb_id,
        ts.last_watched_at                            AS trakt_last_watched_at,
        ts.watch_count                                AS trakt_watch_count,
        ts.trakt_rating,
        ts.trakt_rating_raw,
        ts.trakt_rated_at,
        ts.runtime_minutes                            AS trakt_runtime_minutes,
        ts.status,
        ts.network,
        ts.country                                    AS trakt_country,
        mb.title_key IS NOT NULL                      AS has_moviebuddy,
        ts.title_key IS NOT NULL                      AS has_trakt
    FROM moviebuddy_keyed mb
    FULL OUTER JOIN trakt_shows ts
        ON  mb.title_key    = ts.title_key
        AND mb.release_year = ts.release_year
),

combined AS (
    SELECT
        COALESCE(moviebuddy_title, trakt_title)        AS title,
        'TV Show'                                      AS content_type,
        tyu.release_year,
        COALESCE(
            trakt_rating,
            NULLIF(moviebuddy_rating, 0),
            mr.manual_rating
        )                                             AS rating,
        directors,
        COALESCE(mgn.genres_fr, tgn.genres_fr)        AS genres,
        COALESCE(moviebuddy_runtime_minutes, trakt_runtime_minutes) AS runtime_minutes,
        COALESCE(moviebuddy_tmdb_id, trakt_tmdb_id)    AS tmdb_id,
        DATE(trakt_last_watched_at)                    AS first_watched_date,
        DATE(trakt_last_watched_at)                    AS last_watched_date,
        trakt_watch_count                              AS watch_count,
        trakt_rating,
        trakt_rating_raw,
        trakt_rated_at,
        trakt_show_id,
        trakt_slug,
        trakt_imdb_id,
        status,
        network,
        CASE
            WHEN has_trakt AND has_moviebuddy THEN 'trakt_and_moviebuddy'
            WHEN has_trakt THEN 'trakt'
            ELSE 'moviebuddy'
        END                                           AS source,
        CASE
            WHEN has_trakt AND has_moviebuddy THEN 'title_year'
        END                                           AS match_type,
        COALESCE(cnf_director.country_fr, cnf_trakt.country_fr, adc.country, trakt_country) AS country
    FROM title_year_unified tyu
    LEFT JOIN moviebuddy_genres_normalised mgn
        ON tyu.moviebuddy_movie_id = mgn.movie_id
    LEFT JOIN trakt_genres_normalised tgn
        ON  tyu.title_key    = tgn.title_key
        AND tyu.release_year = tgn.release_year
    LEFT JOIN anime_director_countries adc
        ON lower(trim(SPLIT(tyu.directors, ',')[SAFE_OFFSET(0)])) = adc.director_key
    LEFT JOIN country_name_fr cnf_director
        ON lower(trim(adc.country)) = cnf_director.country_key
    LEFT JOIN country_name_fr cnf_trakt
        ON lower(trim(tyu.trakt_country)) = cnf_trakt.country_key
    LEFT JOIN manual_ratings mr
        ON tyu.title_key = mr.title_key
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['title', 'release_year']) }} AS anime_id,
    *
FROM combined
