WITH source_genres AS (
    SELECT
        'books' AS domain,
        genre AS raw_genre
    FROM {{ ref('stg_csv__bookbuddy') }}
    WHERE genre IS NOT NULL

    UNION ALL

    SELECT
        'movies' AS domain,
        raw_genre
    FROM {{ ref('stg_csv__moviebuddy') }},
        UNNEST(SPLIT(genres, ',')) AS raw_genre
    WHERE genres IS NOT NULL

    UNION ALL

    SELECT
        'music' AS domain,
        raw_genre
    FROM {{ ref('stg_csv__musicbuddy') }},
        UNNEST(SPLIT(genres, ',')) AS raw_genre
    WHERE genres IS NOT NULL

    UNION ALL

    SELECT
        'music' AS domain,
        JSON_VALUE(raw_genre_json) AS raw_genre
    FROM {{ ref('stg_spotify__followed_artists') }},
        UNNEST(JSON_EXTRACT_ARRAY(genres)) AS raw_genre_json
    WHERE genres IS NOT NULL

    UNION ALL

    SELECT
        'movies' AS domain,
        JSON_VALUE(raw_genre_json) AS raw_genre
    FROM {{ ref('stg_trakt__watched_movies') }},
        UNNEST(JSON_EXTRACT_ARRAY(genres)) AS raw_genre_json
    WHERE genres IS NOT NULL

    UNION ALL

    SELECT
        'movies' AS domain,
        JSON_VALUE(raw_genre_json) AS raw_genre
    FROM {{ ref('stg_trakt__watched_shows') }},
        UNNEST(JSON_EXTRACT_ARRAY(genres)) AS raw_genre_json
    WHERE genres IS NOT NULL

    UNION ALL

    SELECT
        'movies' AS domain,
        JSON_VALUE(raw_genre_json) AS raw_genre
    FROM {{ ref('stg_trakt__ratings') }},
        UNNEST(JSON_EXTRACT_ARRAY(genres)) AS raw_genre_json
    WHERE genres IS NOT NULL
),

source_genres_normalised AS (
    SELECT DISTINCT
        domain,
        trim(raw_genre) AS raw_genre,
        lower(trim(raw_genre)) AS raw_genre_key
    FROM source_genres
    WHERE raw_genre IS NOT NULL
      AND trim(raw_genre) != ''
),

mapped_genres AS (
    SELECT DISTINCT
        domain,
        lower(trim(raw_genre)) AS raw_genre_key
    FROM {{ ref('genre_mapping') }}
),

unmapped_genres AS (
    SELECT
        sg.domain,
        sg.raw_genre
    FROM source_genres_normalised sg
    LEFT JOIN mapped_genres gm
        ON  sg.domain = gm.domain
        AND sg.raw_genre_key = gm.raw_genre_key
    WHERE gm.raw_genre_key IS NULL
)

SELECT * FROM unmapped_genres
