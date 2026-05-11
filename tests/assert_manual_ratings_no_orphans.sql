WITH manual_ratings AS (
    SELECT
        domain,
        title,
        author_or_director_or_artist AS creator,
        lower(trim(title)) AS title_key,
        lower(trim(author_or_director_or_artist)) AS creator_key
    FROM {{ ref('manual_ratings') }}
),

mart_items AS (
    SELECT
        'books' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(author)) AS creator_key
    FROM {{ ref('mrt_books__collection') }}

    UNION ALL

    SELECT
        'movies' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(SPLIT(directors, ',')[SAFE_OFFSET(0)])) AS creator_key
    FROM {{ ref('mrt_movies__collection') }}

    UNION ALL

    SELECT
        'music' AS domain,
        lower(trim(title)) AS title_key,
        lower(trim(artist)) AS creator_key
    FROM {{ ref('mrt_music__collection') }}
),

orphaned_manual_ratings AS (
    SELECT
        mr.domain,
        mr.title,
        mr.creator
    FROM manual_ratings mr
    LEFT JOIN mart_items mi
        ON  mr.domain = mi.domain
        AND mr.title_key = mi.title_key
        AND mr.creator_key = mi.creator_key
    WHERE mi.title_key IS NULL
)

SELECT * FROM orphaned_manual_ratings
