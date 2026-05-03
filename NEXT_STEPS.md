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

## Infrastructure and tooling

- [x] `packages.yml` configured with `dbt_utils` and `dbt_expectations`
- [x] `dbt deps` — packages installed
- [x] `.sqlfluff` — configured with dbt templater, BigQuery dialect, project style rules
- [x] `scripts/bq_load.sh` — loads all 5 CSVs into `raw_personal` via `bq load --replace`; supports `--dry-run`
- [x] Confirm `dbt build` passes end-to-end against BigQuery

---

## Future / nice to have

- [x] `seeds/films/film_countries.csv` — (title, release_year, country) mapping for Letterboxd-only films that have no director in `director_countries`; same pattern as existing seeds
- [ ] Looker Studio or Metabase dashboard connected to mart tables
- [ ] Schedule CSV refresh + `dbt build` (cron or Cloud Scheduler)
- [ ] Explore Spotify API via Airbyte to replace/supplement MusicBuddy CSV
- [ ] TMDB-based movie matching once Letterboxd exports include TMDB IDs
