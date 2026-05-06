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
- [x] `scripts/spotify_launchd.plist` — macOS launchd job: daily at 09:30 Europe/Paris,
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

## Evidence.dev dashboard (next priority)

Goal: deploy a portfolio-grade dashboard on top of the mart tables using Evidence.dev (static
site) hosted on Netlify (free tier). See ADR-016 for the full architecture rationale.

### Setup ✅

- [x] Create a new GitHub repo `personal-warehouse-dashboard` for the Evidence project
- [x] Scaffold Evidence project: `npm create evidence@latest`
- [x] Configure the BigQuery connector (project ID + service account credentials)
- [x] Connect the GitHub repo to Netlify (auto-deploy on push)
- [x] Add BigQuery credentials as Netlify environment variables
      Note: Evidence env vars are case-sensitive for the option name portion —
      use `client_email` / `private_key` (lowercase), not `CLIENT_EMAIL` / `PRIVATE_KEY`
- [x] Verify a first successful build on Netlify
- [x] Custom domain configured: https://mediatheque.jeremymarchandeau.com

### Daily refresh automation

- [ ] Generate a Netlify build hook URL
- [ ] Append `curl -X POST <NETLIFY_BUILD_HOOK_URL>` to `scripts/spotify_launchd.plist`
      (after the `dbt build` step) so the dashboard rebuilds daily at 09:30

### Dashboard pages ✅

- [x] **Home** (`/`) — intro, BigValue summary, navigation links
- [x] **Music — Collection** (`/music/collection`) — full album table with Dropdown filters
      on genre, country, source, rated-only toggle; BigValue KPIs
- [x] **Music — Stats** (`/music/stats`) — charts by genre, country, decade, rating
      distribution, top artists
- [x] **Books — Collection** (`/books/collection`) — full book table with filters on
      status, genre, country, read-only toggle; BigValue KPIs
- [x] **Books — Stats** (`/books/stats`) — charts by status, genre, country, decade,
      rating distribution, top authors
- [x] **Movies — Collection** (`/movies/collection`) — full movie/TV table with filters
      on content type, genre, country, watched-only toggle; BigValue KPIs
- [x] **Movies — Stats** (`/movies/stats`) — charts by genre, country, decade, content
      type, rating distribution, films watched per year, top directors
- [x] **Cross-domain — Summary** (`/summary`) — top-level KPIs + bar charts per domain
- [x] **Cross-domain — World map** (`/map`) — AreaMap choropleth (Natural Earth GeoJSON,
      ADM0_A3 key), bar chart top 30 countries, filterable DataTable
- [x] Full French translation of all authored content across all pages

### Polish

- [ ] Custom Evidence theme (colours, typography) aligned with portfolio branding
- [ ] `README.md` in the dashboard repo explaining the stack and how to run locally

---

## Future / nice to have

- [x] `seeds/films/film_countries.csv` — (title, release_year, country) mapping for Letterboxd-only films
- [ ] Schedule CSV refresh + `dbt build` for existing CSV sources (cron or Cloud Scheduler)
- [ ] TMDB-based movie matching once Letterboxd exports include TMDB IDs
- [ ] Deezer ingestion via custom Python script (same pattern as Spotify) if needed
- [ ] `mrt_music__listening_history` — Spotify saved tracks with audio features
      (deferred — audio features endpoint deprecated; all columns NULL for now)

---

## Cross-cutting refactoring (do this before new domains)

These tasks impact existing models and must be addressed first.

### Normalisation seeds (personal-warehouse)

- [ ] Create `seeds/shared/genre_mapping.csv` — `(domain, raw_genre, normalized_genre)` mapping
      Covers: films, books, music, manga, anime (ADR-022)
- [ ] Create `seeds/shared/author_name_mapping.csv` — `(raw_name, canonical_name)` mapping
      Known cases: `Hubert Selby` → `Hubert Selby Jr.` (ADR-023)
- [ ] Create `seeds/shared/country_name_fr.csv` — `(country_en, country_fr)` mapping
      Exposes French country names in mart models (ADR-026)
- [ ] Create `seeds/shared/manual_ratings.csv` — `(domain, title, author_or_director_or_artist, rating, rated_at)` (ADR-024)
- [ ] Update `seeds/_seeds.yml` with documentation for all new seeds

### Books refactoring (personal-warehouse)

- [ ] Remove `status` column from `mrt_books__collection` (ADR-025)
- [ ] Remove `WHERE status = 'Read'` filter from `mrt_books__reading_history` (ADR-025)
- [ ] Apply `genre_mapping` in `int_books__unified` to normalise genres into French
- [ ] Apply `author_name_mapping` in `int_books__unified` to resolve author name variants
- [ ] Apply `manual_ratings` as fallback in `int_books__unified`
- [ ] Exclude manga from `int_books__unified` (`WHERE category != 'Manga'`) (ADR-017)
- [ ] Update `_intermediate__models.yml` and `_mart__models.yml`

### Films refactoring (personal-warehouse)

- [ ] Apply `genre_mapping` in `int_movies__unified` to normalise genres into French
- [ ] Apply `manual_ratings` as fallback in `int_movies__unified`
- [ ] Add `source` column to `mrt_movies__collection`
- [ ] Exclude anime from `int_movies__unified` (ADR-017)
- [ ] Update `_intermediate__models.yml` and `_mart__models.yml`

### Music refactoring (personal-warehouse)

- [ ] Add `media_format` column in `int_music__unified`
      Rule: MusicBuddy → `cd`, Spotify → `digital`, Bandcamp → `digital` (ADR-021)
- [ ] Handle format concatenation when an album appears in multiple sources
      e.g. present in MusicBuddy AND Spotify → `media_format = 'cd, digital'`
- [ ] Apply `genre_mapping` in `int_music__unified` to normalise and clean genres
      (remove `& Country` and other Discogs export artefacts)
- [ ] Apply `manual_ratings` as fallback in `int_music__unified`
- [ ] Prepare vinyl slot in the intermediate (optional join — absent file = no-op)
- [ ] Update `mrt_music__collection` to expose `media_format`
- [ ] Update `_intermediate__models.yml` and `_mart__models.yml`

---

## dbt tests (personal-warehouse)

Priority: **immediate** — set up before or alongside the refactoring.

### Generic tests (in existing YAML files)

- [ ] Verify `not_null` + `unique` are in place on all primary keys across all models
- [ ] `accepted_values` on `domain` in `manual_ratings`: `['books', 'movies', 'music', 'manga', 'anime', 'series']`
- [ ] `accepted_values` on `media_format` in `mrt_music__collection`:
      `['cd', 'vinyl', 'digital', 'cd, digital', 'cd, vinyl', 'vinyl, digital', 'cd, vinyl, digital']`
- [ ] `dbt_expectations.expect_column_values_to_be_between` on all `rating` fields: `min_value=0, max_value=5`
- [ ] `relationships` tests between mart models and their intermediate references on primary keys

### Singular tests (in `tests/`)

- [ ] `tests/assert_no_duplicate_titles_per_domain.sql` — verifies no `(title, artist/author/director)`
      duplicates exist in mart models after deduplication
- [ ] `tests/assert_genre_mapping_coverage.sql` — verifies all raw genre values present in staging
      are covered by `genre_mapping.csv` (or produces a list of unmapped values)
- [ ] `tests/assert_manual_ratings_no_orphans.sql` — verifies every `manual_ratings` entry
      corresponds to an existing item in the relevant mart

### dbt tags

- [ ] Tag all staging models with `tag: staging`, intermediate with `tag: intermediate`,
      mart with `tag: mart` in YAML files (enables `dbt test --select tag:mart`)

---

## New source: Trakt (personal-warehouse)

See ADR-018 and ADR-019.

### Ingestion script

- [ ] Create `scripts/trakt_to_bq.py` - Auth: API key (no OAuth required for public profiles; OAuth if profile is private) - Endpoints: watched movies, watched shows, ratings (movies + shows) - Output: `raw_personal.trakt_watched_movies`, `raw_personal.trakt_watched_shows`,
      `raw_personal.trakt_ratings` - Pattern: full-refresh (same approach as `spotify_to_bq.py`)
- [ ] Add Trakt vars (`TRAKT_API_KEY`, `TRAKT_USERNAME`) to `.env.example`
- [ ] Update `requirements.txt`

### Trakt staging (personal-warehouse)

- [ ] `models/staging/trakt/stg_trakt__watched_movies.sql`
- [ ] `models/staging/trakt/stg_trakt__watched_shows.sql`
- [ ] `models/staging/trakt/stg_trakt__ratings.sql`
- [ ] `models/staging/trakt/_trakt__sources.yml` — source declarations + column docs + tests
- [ ] `models/staging/trakt/_trakt__docs.md` — docs blocks

### Intermediate — update for Trakt

- [ ] Update `int_movies__unified` to include Trakt as a third film source - Matching: `lower(trim(title)) + release_year` (consistent with existing pattern) - Rating priority: `COALESCE(trakt_rating, letterboxd_rating, moviebuddy_rating)` (ADR-019) - Add `source` column: `trakt`, `letterboxd`, `moviebuddy`, or combination
- [ ] Create `int_anime__unified` — filtered Trakt shows + filtered MovieBuddy `TV Shows / Animation` - Rating priority: `COALESCE(trakt_rating, moviebuddy_rating)` (ADR-019)

---

## New source: Bandcamp (personal-warehouse)

See ADR-018 and ADR-020.

### Ingestion

- [ ] Export `bandcamp-data-{date}.zip` from Settings > Data Export on bandcamp.com
- [ ] Extract and place in `data/`: `bandcamp_collection.csv`, `bandcamp_wishlist.csv`
- [ ] Load into BigQuery via `bq load` (update `scripts/bq_load.sh`)
- [ ] Document actual Bandcamp export column names in `_csv__sources.yml`

### Bandcamp staging (personal-warehouse)

- [ ] `models/staging/csv/stg_csv__bandcamp_collection.sql`
- [ ] `models/staging/csv/stg_csv__bandcamp_wishlist.sql`
- [ ] Update `models/staging/csv/_csv__sources.yml` with new source declarations

### Intermediate — update for Bandcamp

- [ ] Update `int_music__unified` to include Bandcamp as a third music source - Matching: `lower(trim(title)) + lower(trim(artist))` - Deduplication: one row per album, `media_format` = concatenated formats (ADR-020) - Metadata priority: MusicBuddy > Bandcamp > Spotify (ADR-020)

---

## New domains: Manga and Anime (personal-warehouse)

See ADR-017.

### Seeds

- [ ] Create `seeds/manga/author_countries.csv` — author → country mapping for manga
- [ ] Create `seeds/anime/director_countries.csv` — director → country mapping for anime
- [ ] Update `seeds/_seeds.yml`

### Staging — no new models needed (data already in existing CSVs)

- [ ] Document in `_csv__sources.yml` that `bookbuddy.category = 'Manga'` → manga domain
- [ ] Document that `moviebuddy.content_type = 'TV Shows' AND genres LIKE '%Animation%'` → anime domain

### Intermediate — new models

- [ ] Create `models/intermediate/manga/int_manga__unified.sql` - Source: `stg_csv__bookbuddy` filtered on `category = 'Manga'` - Enrichment: country from `seeds/manga/author_countries.csv` - Genre normalisation via `genre_mapping`
- [ ] Create `models/intermediate/anime/int_anime__unified.sql` - Source: `stg_csv__moviebuddy` filtered on `content_type = 'TV Shows' AND 'Animation' IN genres` + `stg_trakt__watched_shows` filtered on the same criterion - Rating priority: `COALESCE(trakt_rating, moviebuddy_rating)` (ADR-019) - Genre normalisation via `genre_mapping`
- [ ] Create `models/intermediate/manga/_int_manga__models.yml`
- [ ] Create `models/intermediate/anime/_int_anime__models.yml`
- [ ] Create `models/intermediate/manga/_int_manga__docs.md`
- [ ] Create `models/intermediate/anime/_int_anime__docs.md`

### Mart — new models

- [ ] Create `models/mart/manga/mrt_manga__collection.sql`
- [ ] Create `models/mart/anime/mrt_anime__collection.sql`
- [ ] Update `mrt_media__summary` to include manga and anime domain counts
- [ ] Update `mrt_media__country_index` to include manga and anime rows
- [ ] Create `models/mart/manga/_mart__models.yml` + `_mart__docs.md`
- [ ] Create `models/mart/anime/_mart__models.yml` + `_mart__docs.md`

---

## Dashboard (personal-warehouse-dashboard)

### Immediate fixes

- [ ] **Films** — add `source` column to the Movies Collection page
      (value from `mrt_movies__collection.source`)
- [ ] **Sidebar** — translate to French: `Accueil`, `Livres`, `Films`, `Musique`
      and all navigation labels
- [ ] **Breadcrumb** — translate to French on all pages
- [ ] **Logo** — replace the Evidence logo with the text `Médiathèque de Jeremy`
      (via `evidence.config.yaml` → `title`, or in the layout Svelte component
      depending on the Evidence version in use)

### World map

- [ ] Revise the AreaMap colour palette: - Ocean / map background: very light blue (e.g. `#E8F4FD`) - Countries with items: pink → dark red gradient scaled by item count
      (e.g. `colorScale: ['#FADADD', '#C0392B']`) - Countries with no items: very light grey (e.g. `#F5F5F5`)

### New domains

- [ ] Create page `/manga/collection` — table + KPIs
- [ ] Create page `/manga/stats` — genre, country, author charts
- [ ] Create page `/anime/collection` — table + KPIs
- [ ] Create page `/anime/stats` — genre, country, studio/director charts
- [ ] Update sidebar to include `Manga` and `Animé`
- [ ] Update `/summary` page to include manga and anime counters
- [ ] Update `/map` page to include manga and anime domains

### Music media format

- [ ] Display `media_format` in the Music Collection page (column or badge)
- [ ] Add a `media_format` filter (CD / Vinyl / Digital / All)
- [ ] Add a media format breakdown chart in Music Stats

---

## Recommended execution order

```
1.  Normalisation seeds (genre_mapping, author_name_mapping, country_name_fr, manual_ratings)
2.  dbt tests on existing models
3.  Books refactoring (remove status, genre normalisation, author name variants)
4.  Films refactoring (add source column, genre normalisation, rating priority)
5.  Music refactoring (media_format, genre normalisation)
6.  New source: Trakt (script + staging + intermediate update)
7.  New source: Bandcamp (CSV export + staging + intermediate update)
8.  New domains: manga + anime (intermediate + mart)
9.  Dashboard — immediate fixes (sidebar, breadcrumb, logo, films source, map palette)
10. Dashboard — new domains (manga + anime pages)
11. Dashboard — music media format (filter + chart)
12. Complementary dbt tests (singular tests + tags)
```
