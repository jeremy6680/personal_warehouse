# NEXT_STEPS.md — Current Priorities

Work items are listed in recommended order. Complete items are checked off. Add new items at the bottom of the relevant section.

---

## Staging layer ✅

- [x] `stg_csv__goodreads` — book_id, title, author, year_published, publisher, isbn, rating, source_name
- [x] `stg_csv__bookbuddy` — book_id (surrogate), title, author, genre, category, status, rating, isbn, tags
- [x] `stg_csv__letterboxd` — movie_id (surrogate), watched_date, film_name, release_year, letterboxd_uri, rating
- [x] `stg_csv__moviebuddy` — movie_id (surrogate), title, content_type, release_year, rating, directors, genres, runtime_minutes, tmdb_id
- [x] `stg_csv__musicbuddy` — album_id (surrogate), title, artist, genres, release_year, discogs_release_id, rating
- [x] YAML documentation and tests for all staging models in `_csv__sources.yml`
- [x] Load all five CSVs into BigQuery `raw_personal` dataset via `bq load`

---

## Seeds ✅

- [x] `seeds/books/author_countries.csv` — author → country mapping for `int_books__unified`
- [x] `seeds/films/director_countries.csv` — director → country mapping for `int_movies__unified`
- [x] `seeds/music/artist_countries.csv` — artist → country mapping for `int_music__collection`
- [x] `seeds/_seeds.yml` — YAML documentation and tests for all seeds

---

## Intermediate layer ✅

- [x] `int_books__unified` — three-case union (matched / bookbuddy_only / goodreads_only); ISBN-first matching with title+author fallback; country from `author_countries` seed
- [x] `int_movies__unified` — three-case union (matched / moviebuddy_only / letterboxd_only); Letterboxd rewatches aggregated before matching; title+year matching; country from `director_countries` seed
- [x] `int_music__collection` — MusicBuddy enriched with country from `artist_countries` seed; `artist_display` strips Discogs disambiguation suffixes
- [x] YAML documentation and tests for all intermediate models in `_intermediate__models.yml`

---

## Mart layer ✅

- [x] `mrt_books__reading_history` — finished books with rating, genre, dates (source: `int_books__unified` filtered to `status = 'Read'`)
- [x] `mrt_books__collection` — full book collection (read + unread) with metadata, country, ratings from both sources
- [x] `mrt_movies__watching_history` — movies watched with rating, director, genre, watch date (source: `int_movies__unified` filtered to rows with `first_watched_date IS NOT NULL`)
- [x] `mrt_movies__collection` — full movie/TV collection (watched + wishlist) with metadata
- [x] `mrt_music__collection` — full album collection with genre, artist_display, country
- [x] `mrt_media__summary` — cross-domain aggregate: item counts, avg ratings, monthly pace per domain
- [x] `mrt_media__country_index` — cross-domain country spine: one row per (country, domain, item) across books, movies, and music

---

## Infrastructure and tooling ✅

- [x] `packages.yml` configured with `dbt_utils` and `dbt_expectations`
- [x] `dbt deps` — packages installed
- [x] `.sqlfluff` — configured with dbt templater, BigQuery dialect, project style rules
- [x] `scripts/bq_load.sh` — loads all 5 CSVs into `raw_personal` via `bq load --replace`; supports `--dry-run`
- [x] Confirm `dbt build` passes end-to-end against BigQuery

---

## Spotify ingestion — Python script (next focus)

Goal: replace the manual MusicBuddy CSV refresh with a scheduled Python pipeline that pulls
liked tracks, saved albums, and followed artists from the Spotify API and writes them directly
into BigQuery `raw_personal`.

### Ingestion script

- [ ] Create `scripts/spotify_to_bq.py` — authenticates via Spotipy (OAuth2 PKCE), fetches
      saved albums, liked tracks, and followed artists, writes to BigQuery `raw_personal` dataset
- [ ] Create `scripts/spotify_auth.py` (or inline) — handles token refresh and storage
      (token cached locally, never committed)
- [ ] Add `spotipy` and `google-cloud-bigquery` to `requirements.txt`
- [ ] Add `.env.example` documenting required env vars (`SPOTIFY_CLIENT_ID`,
      `SPOTIFY_CLIENT_SECRET`, `SPOTIFY_REDIRECT_URI`, `GOOGLE_APPLICATION_CREDENTIALS`)
- [ ] Update `.gitignore` — exclude `.env`, `spotify_token_cache` / `.cache`

### BigQuery target tables (in `raw_personal`)

- [ ] `raw_personal.spotify_saved_albums` — album_id, name, artists, release_date,
      genres, total_tracks, added_at
- [ ] `raw_personal.spotify_saved_tracks` — track_id, name, artists, album_name,
      duration_ms, added_at, audio_features (danceability, energy, valence, tempo…)
- [ ] `raw_personal.spotify_followed_artists` — artist_id, name, genres, popularity,
      followers

### Airflow DAG

- [ ] Create `dags/spotify_ingest.py` — daily DAG that runs `spotify_to_bq.py` then
      triggers `dbt build --select tag:spotify`
- [ ] Tag relevant dbt models with `+tag: spotify` in `dbt_project.yml`

### dbt staging models

- [ ] `models/staging/spotify/stg_spotify__saved_albums.sql`
- [ ] `models/staging/spotify/stg_spotify__saved_tracks.sql`
- [ ] `models/staging/spotify/stg_spotify__followed_artists.sql`
- [ ] `models/staging/spotify/_spotify__sources.yml` — source declarations pointing to
      `raw_personal` BigQuery tables

### dbt documentation (mandatory per CLAUDE.md)

- [ ] `models/staging/spotify/_spotify__docs.md` — docs blocks for all three staging models
      and their columns (four-section format for mart models)
- [ ] Update `models/overview.md` — add Spotify as a new source in the data sources table
- [ ] Add column-level descriptions for every column in `_spotify__sources.yml`

### Intermediate update

- [ ] Extend `int_music__collection` (or create `int_music__unified`) to union
      MusicBuddy CSV with Spotify saved albums — dedup on `lower(trim(artist)) + lower(trim(title))`;
      `source_name` column to track origin; document matching strategy in `DECISIONS.md`

### Mart update

- [ ] Extend `mrt_music__collection` to include Spotify-sourced albums and tracks
- [ ] Add `mrt_music__listening_history` (Spotify saved tracks with audio features) if
      the track-level data is rich enough to warrant a separate mart model

---

## Future / nice to have

- [x] `seeds/films/film_countries.csv` — (title, release_year, country) mapping for Letterboxd-only films
- [ ] Looker Studio or Metabase dashboard connected to mart tables
- [ ] Schedule CSV refresh + `dbt build` for existing CSV sources (cron or Cloud Scheduler)
- [ ] TMDB-based movie matching once Letterboxd exports include TMDB IDs
- [ ] Deezer ingestion via custom Python script (same pattern as Spotify) if needed
