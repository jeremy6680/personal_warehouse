# CONTEXT.md — Project Overview and Goals

## Why this project exists

Every media-tracking app is a silo. Goodreads knows what you read; Letterboxd knows what you watched; BookBuddy and MovieBuddy know what's on your shelves. None of them talk to each other, and none of them let you ask cross-domain questions like:

- "What genres do I rate highest across books and films?"
- "How many books/movies did I finish per month this year?"
- "Which authors or directors appear most in my collection?"

This project is the answer: a single analytics warehouse that owns all that data and makes it queryable.

It also serves as a **portfolio project** demonstrating dbt analytics engineering patterns (three-layer architecture, source/ref hygiene, YAML documentation, testing) on a real, personally-meaningful dataset.

---

## Data sources

### Goodreads (`goodreads.csv`)
- Exported from [goodreads.com](https://www.goodreads.com) via the account export feature
- Contains: books read, personal ratings (1–5), shelves (`read` / `to-read` / `currently-reading`), year published, publisher, ISBN
- Primary use: reading history and ratings
- Note: ISBN is exported in Excel `="..."` encoding — stripped in staging

### BookBuddy (`bookbuddy.csv`)
- Exported from the BookBuddy iOS app
- Contains: full book collection (read + unread), genre, category, status, rating (0–5), ISBN, tags
- Complements Goodreads: broader collection scope, richer metadata, but no reading dates

### Letterboxd (`letterboxd.csv`)
- Exported from [letterboxd.com](https://letterboxd.com) via the account export feature
- Contains: movies watched with diary dates and personal ratings (0.5–5 half-stars), Letterboxd URI
- Primary use: movie watching history and ratings
- Note: export does not include TMDB IDs — title + year matching only

### MovieBuddy (`moviebuddy.csv`)
- Exported from the MovieBuddy iOS app
- Contains: full movie and TV collection (watched + wishlist), content type, director(s), genres, runtime, TMDB ID, rating (0–5)
- Complements Letterboxd: covers wishlist/collection, richer metadata (director, cast, TMDB ID)

### MusicBuddy (`musicbuddy.csv`)
- Exported from the MusicBuddy iOS app (backed by Discogs)
- Contains: music album collection — artist, genres, release year, Discogs release ID, rating (0–5)
- Note: artist names may carry Discogs disambiguation suffixes (e.g., "Ayo (2)") — stripped in intermediate

### Spotify (API — `scripts/spotify_to_bq.py`)
- Fetched via the Spotify Web API using Spotipy (OAuth2); written to BigQuery by `scripts/spotify_to_bq.py`
- Three tables: `spotify_saved_albums` (119), `spotify_saved_tracks` (254), `spotify_followed_artists` (67)
- Complements MusicBuddy: richer metadata (total tracks, save date, Spotify ID), API-driven refresh
- Note: `album.genres` is almost always empty in the Spotify API — genres are enriched via the followed artists join in `int_music__unified`
- Note: audio features endpoint (`/audio-features`) deprecated by Spotify for new applications in November 2024 — feature columns are NULL

---

## Goals

### Phase 1 — Staging ✅ Complete
- Clean and standardise every source CSV into a well-typed, consistently-named staging model
- No joins, no business logic — purely rename, cast, deduplicate
- Surrogate keys generated via `dbt_utils.generate_surrogate_key` on natural composite keys

### Phase 2 — Intermediate ✅ Complete
- `int_books__unified` — merges Goodreads reading history with BookBuddy collection metadata; three-case union (matched / bookbuddy_only / goodreads_only); ISBN-first matching with title+author fallback; country enrichment via `author_countries` seed
- `int_movies__unified` — merges MovieBuddy collection with Letterboxd diary; Letterboxd rewatches aggregated to one row per film; three-case union; title+year matching; country enrichment via `director_countries` seed
- `int_music__unified` — merges MusicBuddy with Spotify saved albums; three-case union (matched / musicbuddy_only / spotify_only); title+artist matching; Spotify album genres enriched via followed artists join; country enrichment via `artist_countries` seed

### Phase 3 — Mart ✅ Complete
- `mrt_books__collection` — full book collection (read + unread) with metadata, country, ratings from both sources
- `mrt_movies__collection` — full movie/TV collection (watched + wishlist) with metadata
- `mrt_music__collection` — full album collection across MusicBuddy and Spotify, with source_name, country, ratings
- `mrt_media__summary` — cross-domain aggregate: item counts, avg ratings, monthly pace per domain
- `mrt_media__country_index` — cross-domain country spine: one row per (country, domain, item) across books, movies, and music

### Phase 4 — Spotify API ingestion ✅ Complete
- `scripts/spotify_to_bq.py` — fetches saved albums, saved tracks, followed artists; full-refresh to BigQuery
- Three staging models for Spotify data; integrated into `int_music__unified` and `mrt_music__collection`

### Long-term
- ✅ Visualise in Metabase — self-hosted on Hetzner via Coolify at https://culture.jeremymarchandeau.com
- ✅ Spotify API ingestion via custom Python script
- Schedule automatic refreshes (Spotify script + CSV exports) via Airflow DAG

---

## Seeds

Three reference CSVs live in `seeds/` and are managed by dbt (`dbt seed`):

| Seed | Path | Used by |
|---|---|---|
| `author_countries` | `seeds/books/author_countries.csv` | `int_books__unified` |
| `director_countries` | `seeds/films/director_countries.csv` | `int_movies__unified` |
| `film_countries` | `seeds/films/film_countries.csv` | `int_movies__unified` (fallback for Letterboxd-only rows) |
| `artist_countries` | `seeds/music/artist_countries.csv` | `int_music__unified` |

These are manually maintained reference tables mapping names to countries of origin. Join is always case-insensitive (`lower/trim` on both sides).

---

## Target audience

Personal use only. This is a solo project — no multi-user concerns, no PII beyond self-reported data.
