-- ============================================================
-- Model: int_music__unified
-- Layer: Intermediate
-- Description: Full union of MusicBuddy, Bandcamp collection/wishlist, and
--              Spotify saved albums, deduplicated to one row per album.
--              Matching is on normalized artist + title (ADR-020).
--              Metadata priority: MusicBuddy > Bandcamp > Spotify.
--              media_format concatenates detected source formats:
--                MusicBuddy → 'cd'; Bandcamp/Spotify → 'digital' (ADR-021).
--              Spotify album genres are almost always empty ([]) — enriched via
--              a LEFT JOIN on stg_spotify__followed_artists using the primary
--              artist Spotify ID (first entry in artist_ids JSON array).
--              Genre normalised to French via genre_mapping seed (ADR-022).
--              Manual ratings applied as last-resort fallback (ADR-024).
--              Country name translated to French via country_name_fr (ADR-026).
--              artist_display strips Discogs disambiguation suffixes for
--              MusicBuddy rows (e.g. "Ayo (2)" → "Ayo").
-- Dependencies: stg_csv__musicbuddy, stg_csv__bandcamp_collection,
--               stg_csv__bandcamp_wishlist,
--               stg_spotify__saved_albums, stg_spotify__followed_artists,
--               artist_countries, genre_mapping, manual_ratings, country_name_fr
-- Adapter note: BigQuery-focused model. Uses SAFE_CAST, SAFE_OFFSET,
--               JSON_VALUE / JSON_EXTRACT_ARRAY, and QUALIFY.
-- ============================================================

WITH

musicbuddy AS (
    SELECT * FROM {{ ref('stg_csv__musicbuddy') }}
),

bandcamp_collection AS (
    SELECT
        *,
        'collection' AS bandcamp_origin
    FROM {{ ref('stg_csv__bandcamp_collection') }}
),

bandcamp_wishlist AS (
    SELECT
        *,
        'wishlist' AS bandcamp_origin
    FROM {{ ref('stg_csv__bandcamp_wishlist') }}
),

bandcamp_items AS (
    SELECT * FROM bandcamp_collection
    UNION ALL
    SELECT * FROM bandcamp_wishlist
),

saved_albums AS (
    SELECT * FROM {{ ref('stg_spotify__saved_albums') }}
),

followed_artists AS (
    SELECT * FROM {{ ref('stg_spotify__followed_artists') }}
),

artist_countries AS (
    SELECT
        lower(trim(artist)) AS artist_key,
        country
    FROM {{ ref('artist_countries') }}
),

genre_mapping AS (
    SELECT
        lower(trim(raw_genre)) AS raw_genre_key,
        normalized_genre
    FROM {{ ref('genre_mapping') }}
    WHERE domain = 'music'
),

manual_ratings AS (
    SELECT
        lower(trim(title))                        AS title_key,
        lower(trim(author_or_director_or_artist)) AS creator_key,
        rating                                    AS manual_rating
    FROM {{ ref('manual_ratings') }}
    WHERE domain = 'music'
),

country_name_fr AS (
    SELECT
        lower(trim(country_en)) AS country_key,
        country_fr
    FROM {{ ref('country_name_fr') }}
),

musicbuddy_keyed AS (
    SELECT
        *,
        REGEXP_REPLACE(artist, r' \(\d+\)$', '')  AS artist_display,
        lower(trim(title))                         AS title_key,
        lower(trim(artist))                        AS artist_key,
        lower(trim(REGEXP_REPLACE(artist, r' \(\d+\)$', ''))) AS artist_display_key
    FROM musicbuddy
),

musicbuddy_genres_normalised AS (
    SELECT
        album_id,
        STRING_AGG(
            gm.normalized_genre
            ORDER BY gm.normalized_genre
        ) AS genres_fr
    FROM musicbuddy_keyed mb,
        UNNEST(SPLIT(mb.genres, ',')) AS raw_genre
    LEFT JOIN genre_mapping gm
        ON lower(trim(raw_genre)) = gm.raw_genre_key
    WHERE gm.normalized_genre IS NOT NULL
    GROUP BY album_id
),

bandcamp_keyed AS (
    SELECT
        *,
        lower(trim(title)) AS title_key,
        lower(trim(artist)) AS artist_key
    FROM bandcamp_items
),

spotify_keyed AS (
    SELECT
        sa.*,
        lower(trim(sa.album_name))                                              AS title_key,
        lower(trim(sa.artists))                                                 AS artist_key,
        lower(trim(SPLIT(sa.artists, ',')[SAFE_OFFSET(0)]))                     AS primary_artist_key,
        SAFE_CAST(SPLIT(sa.release_date, '-')[SAFE_OFFSET(0)] AS INT64)         AS release_year,
        {{ dbt_utils.generate_surrogate_key(['album_name', 'artists']) }}       AS surrogate_id
    FROM saved_albums sa
),

spotify_enriched AS (
    SELECT
        sk.*,
        COALESCE(NULLIF(sk.genres, '[]'), fa.genres) AS resolved_genres
    FROM spotify_keyed sk
    LEFT JOIN followed_artists fa
        ON JSON_VALUE(sk.artist_ids, '$[0]') = fa.artist_id
),

spotify_genres_normalised AS (
    SELECT
        surrogate_id,
        STRING_AGG(
            gm.normalized_genre
            ORDER BY gm.normalized_genre
        ) AS genres_fr
    FROM spotify_enriched sp,
        UNNEST(JSON_EXTRACT_ARRAY(sp.resolved_genres)) AS raw_genre_json
    LEFT JOIN genre_mapping gm
        ON lower(trim(JSON_VALUE(raw_genre_json))) = gm.raw_genre_key
    WHERE gm.normalized_genre IS NOT NULL
    GROUP BY surrogate_id
),

source_rows AS (
    SELECT
        mb.album_id                    AS source_album_id,
        mb.title,
        mb.artist,
        mb.artist_display,
        mb.title_key,
        mb.artist_display_key          AS artist_key,
        mgn.genres_fr                  AS genres,
        mb.release_year,
        mb.discogs_release_id,
        CAST(NULL AS STRING)           AS spotify_album_id,
        CAST(NULL AS INT64)            AS total_tracks,
        CAST(NULL AS TIMESTAMP)        AS spotify_added_at,
        CAST(NULL AS INT64)            AS bandcamp_item_id,
        CAST(NULL AS STRING)           AS bandcamp_item_url,
        CAST(NULL AS STRING)           AS bandcamp_added_at,
        CAST(NULL AS STRING)           AS bandcamp_origin,
        mb.rating,
        'musicbuddy'                   AS source_name,
        'cd'                           AS media_format,
        1                              AS media_format_order,
        1                              AS source_rank,
        mb.artist_display_key          AS country_artist_key
    FROM musicbuddy_keyed mb
    LEFT JOIN musicbuddy_genres_normalised mgn ON mb.album_id = mgn.album_id

    UNION ALL

    SELECT
        bc.album_id                    AS source_album_id,
        bc.title,
        bc.artist,
        bc.artist                      AS artist_display,
        bc.title_key,
        bc.artist_key,
        CAST(NULL AS STRING)           AS genres,
        CAST(NULL AS INT64)            AS release_year,
        CAST(NULL AS INT64)            AS discogs_release_id,
        CAST(NULL AS STRING)           AS spotify_album_id,
        CAST(NULL AS INT64)            AS total_tracks,
        CAST(NULL AS TIMESTAMP)        AS spotify_added_at,
        bc.item_id                     AS bandcamp_item_id,
        bc.item_url                    AS bandcamp_item_url,
        bc.added_at                    AS bandcamp_added_at,
        bc.bandcamp_origin,
        CAST(NULL AS FLOAT64)          AS rating,
        'bandcamp'                     AS source_name,
        'digital'                      AS media_format,
        2                              AS media_format_order,
        2                              AS source_rank,
        bc.artist_key                  AS country_artist_key
    FROM bandcamp_keyed bc

    UNION ALL

    SELECT
        sp.surrogate_id                AS source_album_id,
        sp.album_name                  AS title,
        sp.artists                     AS artist,
        sp.artists                     AS artist_display,
        sp.title_key,
        sp.artist_key,
        sgn.genres_fr                  AS genres,
        sp.release_year,
        CAST(NULL AS INT64)            AS discogs_release_id,
        sp.album_id                    AS spotify_album_id,
        sp.total_tracks,
        sp.added_at                    AS spotify_added_at,
        CAST(NULL AS INT64)            AS bandcamp_item_id,
        CAST(NULL AS STRING)           AS bandcamp_item_url,
        CAST(NULL AS STRING)           AS bandcamp_added_at,
        CAST(NULL AS STRING)           AS bandcamp_origin,
        CAST(NULL AS FLOAT64)          AS rating,
        'spotify'                      AS source_name,
        'digital'                      AS media_format,
        2                              AS media_format_order,
        3                              AS source_rank,
        sp.primary_artist_key          AS country_artist_key
    FROM spotify_enriched sp
    LEFT JOIN spotify_genres_normalised sgn ON sp.surrogate_id = sgn.surrogate_id
),

preferred_metadata AS (
    SELECT *
    FROM source_rows
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY title_key, artist_key
        ORDER BY source_rank, source_album_id
    ) = 1
),

source_rollup AS (
    SELECT
        title_key,
        artist_key,
        MAX(discogs_release_id)         AS discogs_release_id,
        MAX(spotify_album_id)           AS spotify_album_id,
        MAX(total_tracks)               AS total_tracks,
        MAX(spotify_added_at)           AS spotify_added_at,
        MAX(bandcamp_item_id)           AS bandcamp_item_id,
        MAX(bandcamp_item_url)          AS bandcamp_item_url,
        MAX(bandcamp_added_at)          AS bandcamp_added_at,
        STRING_AGG(DISTINCT bandcamp_origin, ', ' ORDER BY bandcamp_origin) AS bandcamp_origin,
        MAX(CASE WHEN source_name = 'musicbuddy' THEN 1 ELSE 0 END) AS has_musicbuddy,
        MAX(CASE WHEN source_name = 'bandcamp' THEN 1 ELSE 0 END)   AS has_bandcamp,
        MAX(CASE WHEN source_name = 'spotify' THEN 1 ELSE 0 END)    AS has_spotify,
        COUNT(DISTINCT source_name)     AS source_count
    FROM source_rows
    GROUP BY title_key, artist_key
),

format_rows AS (
    SELECT DISTINCT
        title_key,
        artist_key,
        media_format,
        media_format_order
    FROM source_rows
),

media_formats AS (
    SELECT
        title_key,
        artist_key,
        STRING_AGG(media_format, ', ' ORDER BY media_format_order) AS media_format
    FROM format_rows
    GROUP BY title_key, artist_key
),

combined AS (
    SELECT
        pm.source_album_id              AS album_id,
        pm.title,
        pm.artist,
        pm.artist_display,
        pm.genres,
        pm.release_year,
        sr.discogs_release_id,
        sr.spotify_album_id,
        sr.total_tracks,
        sr.spotify_added_at,
        sr.bandcamp_item_id,
        sr.bandcamp_item_url,
        sr.bandcamp_added_at,
        sr.bandcamp_origin,
        COALESCE(pm.rating, mr.manual_rating) AS rating,
        COALESCE(cnf.country_fr, ac.country)  AS country,
        CASE
            WHEN sr.has_musicbuddy = 1 AND sr.has_bandcamp = 1 AND sr.has_spotify = 1
                THEN 'musicbuddy_and_bandcamp_and_spotify'
            WHEN sr.has_musicbuddy = 1 AND sr.has_bandcamp = 1
                THEN 'musicbuddy_and_bandcamp'
            WHEN sr.has_musicbuddy = 1 AND sr.has_spotify = 1
                THEN 'musicbuddy_and_spotify'
            WHEN sr.has_bandcamp = 1 AND sr.has_spotify = 1
                THEN 'bandcamp_and_spotify'
            WHEN sr.has_musicbuddy = 1
                THEN 'musicbuddy'
            WHEN sr.has_bandcamp = 1
                THEN 'bandcamp'
            ELSE 'spotify'
        END AS source_name,
        CASE WHEN sr.source_count > 1 THEN 'title_artist' END AS match_type,
        mf.media_format
    FROM preferred_metadata pm
    INNER JOIN source_rollup sr
        ON  pm.title_key = sr.title_key
        AND pm.artist_key = sr.artist_key
    INNER JOIN media_formats mf
        ON  pm.title_key = mf.title_key
        AND pm.artist_key = mf.artist_key
    LEFT JOIN artist_countries ac
        ON pm.country_artist_key = ac.artist_key
    LEFT JOIN country_name_fr cnf
        ON lower(trim(ac.country)) = cnf.country_key
    LEFT JOIN manual_ratings mr
        ON  pm.title_key  = mr.title_key
        AND pm.artist_key = mr.creator_key
)

SELECT
    album_id,
    title,
    artist,
    artist_display,
    genres,
    release_year,
    discogs_release_id,
    spotify_album_id,
    total_tracks,
    spotify_added_at,
    bandcamp_item_id,
    bandcamp_item_url,
    bandcamp_added_at,
    bandcamp_origin,
    rating,
    country,
    source_name,
    match_type,
    media_format
FROM combined
