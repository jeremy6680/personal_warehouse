-- ============================================================
-- Model: int_music__collection
-- Layer: Intermediate
-- Description: MusicBuddy collection enriched with artist country of origin.
--              country is joined from the artist_countries seed on normalized
--              artist name. artist_display strips Discogs disambiguation suffixes
--              (e.g. "Ayo (2)" → "Ayo") for clean presentation.
--              Single-source model — Discogs API enrichment
--              (title, label, format, release country) can be added here
--              when a stg_api__discogs staging model is available.
-- Dependencies: stg_csv__musicbuddy, artist_countries
-- Adapter note: Works on BigQuery, DuckDB, and PostgreSQL.
-- ============================================================

WITH

musicbuddy AS (
    SELECT * FROM {{ ref('stg_csv__musicbuddy') }}
),

artist_countries AS (
    SELECT
        lower(trim(artist)) AS artist_key,
        country
    FROM {{ ref('artist_countries') }}
),

enriched AS (
    SELECT
        mb.album_id,
        mb.title,
        mb.artist,
        REGEXP_REPLACE(mb.artist, r' \(\d+\)$', '') AS artist_display,
        mb.genres,
        mb.release_year,
        mb.discogs_release_id,
        mb.rating,
        ac.country
    FROM musicbuddy mb
    LEFT JOIN artist_countries ac ON lower(trim(mb.artist)) = ac.artist_key
)

SELECT * FROM enriched
