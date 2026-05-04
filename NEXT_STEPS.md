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

## Spotify ingestion ✅

Goal: replace the manual MusicBuddy CSV refresh with a scheduled Python pipeline that pulls
liked tracks, saved albums, and followed artists from the Spotify API and writes them directly
into BigQuery `raw_personal`.

### Ingestion script ✅

- [x] `scripts/spotify_to_bq.py` — authenticates via Spotipy (OAuth2), fetches saved albums,
      saved tracks, and followed artists; full-refresh write to BigQuery `raw_personal`
- [x] Token auth inline — OAuth2 token cached in `.spotify_cache` (git-ignored)
- [x] `requirements.txt` — spotipy, google-cloud-bigquery, python-dotenv
- [x] `.env.example` — documents required env vars
- [x] `.gitignore` — `.spotify_cache` excluded

### BigQuery target tables (in `raw_personal`) ✅

- [x] `raw_personal.spotify_saved_albums` — 119 rows
- [x] `raw_personal.spotify_saved_tracks` — 254 rows (audio features NULL — endpoint deprecated Nov 2024)
- [x] `raw_personal.spotify_followed_artists` — 67 rows

### Scheduling

- [x] `dags/spotify_ingest.py` — Airflow DAG written (kept as portfolio artefact); not used
      in practice due to persistent macOS SIGSEGV — see ADR-015
- [ ] `scripts/spotify_launchd.plist` — macOS launchd job: daily at 09:30 Europe/Paris,
      runs `spotify_to_bq.py` then `dbt build --select tag:spotify+`

### dbt staging models ✅

- [x] `models/staging/spotify/stg_spotify__saved_albums.sql`
- [x] `models/staging/spotify/stg_spotify__saved_tracks.sql`
- [x] `models/staging/spotify/stg_spotify__followed_artists.sql`
- [x] `models/staging/spotify/_spotify__sources.yml` — source declarations + full column docs + tests

### Intermediate update ✅

- [x] `int_music__unified` — three-case union (matched / musicbuddy_only / spotify_only);
      title+artist matching; Spotify album genres enriched via followed_artists join;
      release_year extracted from Spotify variable-precision release_date string

### Mart update

- [x] `mrt_music__collection` — extended to source from `int_music__unified`; adds
      spotify_album_id, total_tracks, spotify_added_at, source_name columns
- [ ] `mrt_music__listening_history` — Spotify saved tracks with audio features
      (deferred — audio features endpoint deprecated; columns are all NULL for now)

---

## Future / nice to have

- [x] `seeds/films/film_countries.csv` — (title, release_year, country) mapping for Letterboxd-only films
- [ ] Looker Studio or Metabase dashboard connected to mart tables
- [ ] Schedule CSV refresh + `dbt build` for existing CSV sources (cron or Cloud Scheduler)
- [ ] TMDB-based movie matching once Letterboxd exports include TMDB IDs
- [ ] Deezer ingestion via custom Python script (same pattern as Spotify) if needed
