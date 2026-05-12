WITH mart_items AS (
    SELECT
        'books' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(author)) AS creator_key,
        title,
        author AS creator
    FROM {{ ref('mrt_books__collection') }}

    UNION ALL

    SELECT
        'movies' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(SPLIT(directors, ',')[SAFE_OFFSET(0)])) AS creator_key,
        title,
        SPLIT(directors, ',')[SAFE_OFFSET(0)] AS creator
    FROM {{ ref('mrt_movies__collection') }}

    UNION ALL

    SELECT
        'music' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(artist)) AS creator_key,
        title,
        artist AS creator
    FROM {{ ref('mrt_music__collection') }}

    UNION ALL

    SELECT
        'manga' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(author)) AS creator_key,
        title,
        author AS creator
    FROM {{ ref('mrt_manga__collection') }}

    UNION ALL

    SELECT
        'anime' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(SPLIT(directors, ',')[SAFE_OFFSET(0)])) AS creator_key,
        title,
        SPLIT(directors, ',')[SAFE_OFFSET(0)] AS creator
    FROM {{ ref('mrt_anime__collection') }}
),

duplicates AS (
    SELECT
        domain,
        title_key,
        creator_key,
        count(*) AS duplicate_count,
        STRING_AGG(title, ' | ' ORDER BY title) AS duplicate_titles,
        STRING_AGG(COALESCE(creator, '<unknown>'), ' | ' ORDER BY creator) AS duplicate_creators
    FROM mart_items
    WHERE title_key IS NOT NULL
      AND creator_key IS NOT NULL
    GROUP BY 1, 2, 3
    HAVING count(*) > 1
)

SELECT * FROM duplicates
