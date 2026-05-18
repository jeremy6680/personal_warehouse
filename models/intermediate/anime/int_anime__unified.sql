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
        normalized_genre,
        lower(trim(raw_genre)) AS raw_genre_key
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'movies'
),

anime_director_countries AS (
    SELECT
        country,
        lower(trim(director)) AS director_key
    FROM {{ ref('anime_director_countries') }}
),

manual_ratings AS (
    SELECT
        rating AS manual_rating,
        lower(trim(title)) AS title_key
    FROM {{ ref('manual_ratings') }}
    WHERE domain = 'anime'
),

country_name_fr AS (
    SELECT
        country_fr,
        lower(trim(country_en)) AS country_key
    FROM {{ ref('country_name_fr') }}
),

moviebuddy_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM moviebuddy
    WHERE
        content_type = 'TV Show'
        AND lower(genres) LIKE '%animation%'
),

moviebuddy_genres_normalised AS (
    SELECT
        movie_id,
        string_agg(
            gm.normalized_genre
            ORDER BY gm.normalized_genre
        ) AS genres_fr
    FROM moviebuddy_keyed AS mb,
        unnest(split(mb.genres, ',')) AS raw_genre
    LEFT JOIN genre_mapping AS gm
        ON lower(trim(raw_genre)) = gm.raw_genre_key
    WHERE gm.normalized_genre IS NOT NULL
    GROUP BY movie_id
),

trakt_watched_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM trakt_watched_shows
    WHERE
        lower(genres) LIKE '%animation%'
        OR lower(genres) LIKE '%anime%'
),

trakt_ratings_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key
    FROM trakt_ratings
    WHERE
        lower(genres) LIKE '%animation%'
        OR lower(genres) LIKE '%anime%'
    QUALIFY
        row_number() OVER (
            PARTITION BY lower(trim(title)), release_year
            ORDER BY rated_at DESC
        ) = 1
),

trakt_shows AS (
    SELECT
        tw.last_watched_at,
        tw.watch_count,
        tr.rating AS trakt_rating,
        tr.rating_raw AS trakt_rating_raw,
        tr.rated_at AS trakt_rated_at,
        tw.status,
        tw.network,
        coalesce(tw.title_key, tr.title_key) AS title_key,
        coalesce(tw.title, tr.title) AS title,
        coalesce(tw.release_year, tr.release_year) AS release_year,
        coalesce(tw.trakt_show_id, tr.trakt_id) AS trakt_show_id,
        coalesce(tw.slug, tr.slug) AS trakt_slug,
        coalesce(tw.imdb_id, tr.imdb_id) AS trakt_imdb_id,
        coalesce(tw.tmdb_id, tr.tmdb_id) AS trakt_tmdb_id,
        coalesce(tw.genres, tr.genres) AS genres,
        coalesce(tw.runtime_minutes, tr.runtime_minutes) AS runtime_minutes,
        coalesce(tw.country, tr.country) AS country
    FROM trakt_watched_keyed AS tw
    FULL OUTER JOIN trakt_ratings_keyed AS tr
        ON
            tw.title_key = tr.title_key
            AND tw.release_year = tr.release_year
),

trakt_genres_normalised AS (
    SELECT
        title_key,
        release_year,
        string_agg(
            gm.normalized_genre
            ORDER BY gm.normalized_genre
        ) AS genres_fr
    FROM trakt_shows AS ts,
        unnest(json_extract_array(ts.genres)) AS raw_genre_json
    LEFT JOIN genre_mapping AS gm
        ON lower(trim(json_value(raw_genre_json))) = gm.raw_genre_key
    WHERE gm.normalized_genre IS NOT NULL
    GROUP BY title_key, release_year
),

title_year_unified AS (
    SELECT
        mb.movie_id AS moviebuddy_movie_id,
        mb.title AS moviebuddy_title,
        ts.title AS trakt_title,
        mb.rating AS moviebuddy_rating,
        mb.directors,
        mb.runtime_minutes AS moviebuddy_runtime_minutes,
        mb.tmdb_id AS moviebuddy_tmdb_id,
        ts.trakt_show_id,
        ts.trakt_slug,
        ts.trakt_imdb_id,
        ts.trakt_tmdb_id,
        ts.last_watched_at AS trakt_last_watched_at,
        ts.watch_count AS trakt_watch_count,
        ts.trakt_rating,
        ts.trakt_rating_raw,
        ts.trakt_rated_at,
        ts.runtime_minutes AS trakt_runtime_minutes,
        ts.status,
        ts.network,
        ts.country AS trakt_country,
        coalesce(mb.title_key, ts.title_key) AS title_key,
        coalesce(mb.release_year, ts.release_year) AS release_year,
        mb.title_key IS NOT NULL AS has_moviebuddy,
        ts.title_key IS NOT NULL AS has_trakt
    FROM moviebuddy_keyed AS mb
    FULL OUTER JOIN trakt_shows AS ts
        ON
            mb.title_key = ts.title_key
            AND mb.release_year = ts.release_year
),

combined AS (
    SELECT
        'TV Show' AS content_type,
        tyu.release_year,
        directors,
        cast(NULL AS DATE) AS first_watched_date,
        trakt_watch_count AS watch_count,
        trakt_rating,
        trakt_rating_raw,
        trakt_rated_at,
        -- Trakt's show-level API only exposes last_watched_at — first watch date is unavailable.
        trakt_show_id,
        trakt_slug,
        trakt_imdb_id,
        status,
        network,
        coalesce(moviebuddy_title, trakt_title) AS title,
        coalesce(
            trakt_rating,
            nullif(moviebuddy_rating, 0),
            mr.manual_rating
        ) AS rating,
        coalesce(mgn.genres_fr, tgn.genres_fr) AS genres,
        coalesce(moviebuddy_runtime_minutes, trakt_runtime_minutes) AS runtime_minutes,
        coalesce(moviebuddy_tmdb_id, trakt_tmdb_id) AS tmdb_id,
        date(trakt_last_watched_at) AS last_watched_date,
        CASE
            WHEN has_trakt AND has_moviebuddy THEN 'trakt_and_moviebuddy'
            WHEN has_trakt THEN 'trakt'
            ELSE 'moviebuddy'
        END AS source,
        CASE
            WHEN has_trakt AND has_moviebuddy THEN 'title_year'
        END AS match_type,
        coalesce(cnf_director.country_fr, cnf_trakt.country_fr, adc.country, trakt_country) AS country
    FROM title_year_unified AS tyu
    LEFT JOIN moviebuddy_genres_normalised AS mgn
        ON tyu.moviebuddy_movie_id = mgn.movie_id
    LEFT JOIN trakt_genres_normalised AS tgn
        ON
            tyu.title_key = tgn.title_key
            AND tyu.release_year = tgn.release_year
    LEFT JOIN anime_director_countries AS adc
        ON lower(trim(split(tyu.directors, ',')[safe_offset(0)])) = adc.director_key
    LEFT JOIN country_name_fr AS cnf_director
        ON lower(trim(adc.country)) = cnf_director.country_key
    LEFT JOIN country_name_fr AS cnf_trakt
        ON lower(trim(tyu.trakt_country)) = cnf_trakt.country_key
    LEFT JOIN manual_ratings AS mr
        ON tyu.title_key = mr.title_key
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['title', 'release_year']) }} AS anime_id,
    *
FROM combined
