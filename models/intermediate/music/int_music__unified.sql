-- ============================================================
-- Model: int_music__unified
-- Layer: Intermediate
-- Description: Full union of MusicBuddy and Spotify saved albums, deduplicated
--              to one row per album. Three output cases:
--                - matched: one row with columns from both sources
--                - musicbuddy_only: in MusicBuddy but not saved on Spotify
--                - spotify_only: saved on Spotify but not in MusicBuddy
--              Matching is on normalized artist + title (single pass).
--              Spotify album genres are almost always empty ([]) — enriched via
--              a LEFT JOIN on stg_spotify__followed_artists using the primary
--              artist Spotify ID (first entry in artist_ids JSON array).
--              country is joined from the artist_countries seed on normalized
--              artist name (primary artist for Spotify multi-artist albums).
--              artist_display strips Discogs disambiguation suffixes for
--              MusicBuddy rows (e.g. "Ayo (2)" → "Ayo").
-- Dependencies: stg_csv__musicbuddy, stg_spotify__saved_albums,
--               stg_spotify__followed_artists, artist_countries
-- Adapter note: SPLIT and SAFE_OFFSET used for release_year extraction and
--               primary artist key — supported on BigQuery and DuckDB.
--               JSON_VALUE used for artist_ids — BigQuery only.
--               For PostgreSQL: replace SPLIT/SAFE_OFFSET with split_part(),
--               and JSON_VALUE with jsonb operators.
-- ============================================================

WITH

musicbuddy AS (
    SELECT * FROM {{ ref('stg_csv__musicbuddy') }}
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

musicbuddy_keyed AS (
    SELECT
        *,
        REGEXP_REPLACE(artist, r' \(\d+\)$', '')  AS artist_display,
        lower(trim(title))                         AS title_key,
        lower(trim(artist))                        AS artist_key
    FROM musicbuddy
),

spotify_keyed AS (
    SELECT
        sa.*,
        lower(trim(sa.album_name))                                              AS title_key,
        lower(trim(sa.artists))                                                 AS artist_key,
        -- Primary artist key for country seed lookup
        lower(trim(SPLIT(sa.artists, ',')[SAFE_OFFSET(0)]))                     AS primary_artist_key,
        -- Year extracted from variable-precision release_date string
        SAFE_CAST(SPLIT(sa.release_date, '-')[SAFE_OFFSET(0)] AS INT64)         AS release_year,
        {{ dbt_utils.generate_surrogate_key(['album_name', 'artists']) }}       AS surrogate_id
    FROM saved_albums sa
),

-- Enrich Spotify albums with genres from followed artists.
-- album.genres is almost always [] in the Spotify API — genres are reliable on artists.
spotify_enriched AS (
    SELECT
        sk.*,
        COALESCE(NULLIF(sk.genres, '[]'), fa.genres) AS resolved_genres
    FROM spotify_keyed sk
    LEFT JOIN followed_artists fa
        ON JSON_VALUE(sk.artist_ids, '$[0]') = fa.artist_id
),

-- Single-pass match on normalized artist + title
title_artist_matches AS (
    SELECT
        mb.album_id      AS mb_album_id,
        sp.surrogate_id  AS sp_surrogate_id
    FROM musicbuddy_keyed mb
    INNER JOIN spotify_enriched sp
        ON  mb.title_key  = sp.title_key
        AND mb.artist_key = sp.artist_key
),

-- Case 1: album present in both sources
matched AS (
    SELECT
        mb.album_id,
        mb.title,
        mb.artist,
        mb.artist_display,
        mb.genres,
        mb.release_year,
        mb.discogs_release_id,
        sp.album_id                  AS spotify_album_id,
        sp.total_tracks,
        sp.added_at                  AS spotify_added_at,
        mb.rating,
        ac.country,
        'both'                       AS source_name,
        'title_artist'               AS match_type
    FROM title_artist_matches         m
    INNER JOIN musicbuddy_keyed  mb  ON m.mb_album_id     = mb.album_id
    INNER JOIN spotify_enriched  sp  ON m.sp_surrogate_id = sp.surrogate_id
    LEFT JOIN artist_countries   ac  ON mb.artist_key     = ac.artist_key
),

-- Case 2: album in MusicBuddy only
musicbuddy_only AS (
    SELECT
        mb.album_id,
        mb.title,
        mb.artist,
        mb.artist_display,
        mb.genres,
        mb.release_year,
        mb.discogs_release_id,
        CAST(NULL AS STRING)         AS spotify_album_id,
        CAST(NULL AS INT64)          AS total_tracks,
        CAST(NULL AS TIMESTAMP)      AS spotify_added_at,
        mb.rating,
        ac.country,
        'musicbuddy'                 AS source_name,
        CAST(NULL AS STRING)         AS match_type
    FROM musicbuddy_keyed mb
    LEFT JOIN title_artist_matches m ON mb.album_id    = m.mb_album_id
    LEFT JOIN artist_countries    ac ON mb.artist_key  = ac.artist_key
    WHERE m.mb_album_id IS NULL
),

-- Case 3: album in Spotify only
spotify_only AS (
    SELECT
        sp.surrogate_id              AS album_id,
        sp.album_name                AS title,
        sp.artists                   AS artist,
        sp.artists                   AS artist_display,
        sp.resolved_genres           AS genres,
        sp.release_year,
        CAST(NULL AS INT64)          AS discogs_release_id,
        sp.album_id                  AS spotify_album_id,
        sp.total_tracks,
        sp.added_at                  AS spotify_added_at,
        CAST(NULL AS FLOAT64)        AS rating,
        ac.country,
        'spotify'                    AS source_name,
        CAST(NULL AS STRING)         AS match_type
    FROM spotify_enriched sp
    LEFT JOIN title_artist_matches m ON sp.surrogate_id        = m.sp_surrogate_id
    LEFT JOIN artist_countries    ac ON sp.primary_artist_key  = ac.artist_key
    WHERE m.sp_surrogate_id IS NULL
),

combined AS (
    SELECT * FROM matched
    UNION ALL
    SELECT * FROM musicbuddy_only
    UNION ALL
    SELECT * FROM spotify_only
)

SELECT * FROM combined
