# STRUCTURE.md — Folder and File Structure

This document explains what every folder and file in this project is for and how they relate to each other.

---

## Repository layout

personal_warehouse/ ← dbt project root (git repo)
│
├── data/ ← Raw CSV exports (loaded into BigQuery externally)
│ ├── bookbuddy.csv ← BookBuddy full library export
│ ├── goodreads.csv ← Goodreads reading export
│ ├── letterboxd.csv ← Letterboxd diary export
│ ├── moviebuddy.csv ← MovieBuddy full collection export
│ └── musicbuddy.csv ← MusicBuddy album collection export
│
├── models/
│ ├── overview.md ← dbt docs landing page (overview block)
│ ├── staging/
│ │ ├── csv/ ← CSV-backed sources (raw_personal dataset)
│ │ │ ├── _csv__sources.yml ← Source declarations + staging model docs
│ │ │ ├── stg_csv__goodreads.sql
│ │ │ ├── stg_csv__bookbuddy.sql
│ │ │ ├── stg_csv__letterboxd.sql
│ │ │ ├── stg_csv__moviebuddy.sql
│ │ │ ├── stg_csv__musicbuddy.sql
│ │ │ ├── stg_csv__bandcamp_collection.sql
│ │ │ └── stg_csv__bandcamp_wishlist.sql
│ │ ├── spotify/ ← Spotify API source (raw_personal dataset)
│ │ │ ├── _spotify__sources.yml
│ │ │ ├── stg_spotify__saved_albums.sql
│ │ │ ├── stg_spotify__saved_tracks.sql
│ │ │ └── stg_spotify__followed_artists.sql
│ │ └── trakt/ ← Trakt API source (raw_personal dataset)
│ │   ├── _trakt__sources.yml
│ │   ├── _trakt__docs.md
│ │   ├── stg_trakt__watched_movies.sql
│ │   ├── stg_trakt__watched_shows.sql
│ │   └── stg_trakt__ratings.sql
│ │
│ ├── intermediate/
│ │ ├── _intermediate__models.yml ← Intermediate model docs and tests (all domains)
│ │ ├── books/
│ │ │ └── int_books__unified.sql
│ │ ├── films/
│ │ │ └── int_movies__unified.sql
│ │ ├── music/
│ │ │ ├── int_music__collection.sql ← Orphan — superseded by int_music__unified
│ │ │ └── int_music__unified.sql ← MusicBuddy + Bandcamp + Spotify union
│ │ ├── manga/
│ │ │ └── int_manga__unified.sql
│ │ └── anime/
│ │   └── int_anime__unified.sql
│ │
│ └── mart/
│ ├── _mart__models.yml
│ ├── books/
│ │ ├── mrt_books__reading_history.sql
│ │ └── mrt_books__collection.sql
│ ├── films/
│ │ ├── mrt_movies__watching_history.sql
│ │ └── mrt_movies__collection.sql
│ ├── music/
│ │ └── mrt_music__collection.sql ← listened/liked music library
│ ├── manga/
│ │ └── mrt_manga__collection.sql
│ ├── anime/
│ │ └── mrt_anime__collection.sql
│ └── cross_domain/
│   ├── mrt_media__summary.sql
│   └── mrt_media__country_index.sql
│
├── seeds/ ← Static reference CSVs managed by dbt seed
│ ├── _seeds.yml ← Seed documentation and tests (all domains)
│ ├── books/
│ │ └── author_countries.csv
│ ├── films/
│ │ ├── director_countries.csv
│ │ └── film_countries.csv
│ ├── music/
│ │ └── artist_countries.csv
│ ├── manga/
│ │ └── manga_author_countries.csv
│ ├── anime/
│ │ └── anime_director_countries.csv
│ ├── shared/
│ │ ├── author_name_mapping.csv
│ │ ├── country_name_fr.csv
│ │ ├── genre_mapping.csv
│ │ └── manual_ratings.csv
│ └── geography/
│   └── country_iso_codes.csv
│
├── scripts/
│ ├── bq_load.sh ← Loads CSV files into raw_personal via bq load
│ ├── spotify_to_bq.py ← Fetches Spotify data via API → writes to raw_personal
│ ├── trakt_to_bq.py ← Fetches Trakt watched/rating data via API → writes to raw_personal
│ ├── bandcamp_to_bq.py ← Fetches Bandcamp collection/wishlist via internal API → writes to raw_personal
│ ├── run_spotify_refresh.sh ← launchd entrypoint: Spotify ingest → dbt build → Netlify hook
│ └── spotify_launchd.plist ← LaunchAgent template for the daily Spotify refresh
│
├── dags/
│ └── spotify_ingest.py ← Airflow DAG kept as a portfolio artefact; launchd is used locally
│
├── analyses/ ← Ad-hoc SQL (not materialised by dbt)
├── macros/ ← Reusable Jinja macros
│ └── tests/ ← Custom generic test macros
├── snapshots/ ← SCD Type 2 snapshots
├── tests/ ← Singular (one-off) data tests
├── target/ ← Compiled artifacts (git-ignored)
├── logs/ ← dbt logs (git-ignored)
│
├── requirements.txt ← Python dependencies (spotipy, google-cloud-bigquery…)
├── .env.example ← Env var template (SPOTIFY_CLIENT_ID, etc.) — .env not committed
├── dbt_project.yml ← Project config (name, paths, materialisation defaults)
├── packages.yml ← dbt package dependencies (dbt_utils, dbt_expectations)
├── profiles.yml ← NOT committed — lives at ~/.dbt/profiles.yml
├── .gitignore
│
├── CLAUDE.md ← AI assistant instructions and code standards
├── CONTEXT.md ← Project goals and data source descriptions
├── DECISIONS.md ← Architecture decision records
├── NEXT_STEPS.md ← Current priorities
└── STRUCTURE.md ← This file

---

## BigQuery datasets

| Dataset              | Contenu                                                                                                       | Alimenté par              |
| -------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `raw_personal`       | Tables brutes de toutes les sources : CSV exports (`bookbuddy`, `goodreads`, etc.) + tables API (`spotify_*`, `trakt_*`, `bandcamp_*`) | `bq load`, scripts Python |
| `personal_warehouse` | Vues et tables dbt : `stg_*`, `int_*`, `mrt_*`                                                                | `dbt build`               |

Toutes les sources brutes atterrissent dans `raw_personal`, quelle que soit leur méthode d'ingestion.
Les staging models y accèdent via `source()` ; dbt ne touche jamais directement à ce dataset.

---

## Key distinctions

### `data/` vs `seeds/`

|                 | `data/`                     | `seeds/`         |
| --------------- | --------------------------- | ---------------- |
| Who loads it?   | External (bq load, scripts) | dbt (`dbt seed`) |
| Source of truth | BigQuery `raw_personal`     | dbt repo         |
| Size            | Can be large                | Small only       |
| Changes         | From upstream app exports   | Manually edited  |
| Referenced via  | `source()`                  | `ref()`          |

All five media-tracking CSVs belong in `data/` because they come from external apps and may be
replaced by API integrations in the future. The `*_countries` seeds belong in `seeds/` because
they are small, manually maintained reference tables.

### `models/staging/<source>/`

Each source group gets its own sub-folder and its own `_<source>__sources.yml`. CSV, Spotify,
Trakt, and Bandcamp-backed staging models all point to `raw_personal` as their BigQuery dataset —
the sub-folder separation is a dbt organisation convention, not a warehouse-level distinction.

### `scripts/` vs `dags/`

- `scripts/` — standalone Python/shell scripts that can be run directly (`python spotify_to_bq.py`)
- `dags/` — Airflow DAG definitions kept as portfolio artefacts; local scheduling currently uses
  macOS launchd via `scripts/run_spotify_refresh.sh`

---

## Naming conventions

### SQL files

- Staging: `stg_<source>__<entity>.sql`
- Intermediate: `int_<domain>__<description>.sql`
- Mart: `mrt_<domain>__<entity>.sql`

Double underscore `__` separates source/domain from entity.

### YAML files

- Sources + staging docs: `_<source>__sources.yml` (e.g., `_csv__sources.yml`, `_spotify__sources.yml`)
- Intermediate docs: `_intermediate__models.yml`
- Mart docs: `_mart__models.yml`
- Seeds docs: `_seeds.yml`

### BigQuery raw tables — API prefixes

API tables in `raw_personal` use source prefixes to avoid collisions with CSV-backed tables:
`spotify_saved_albums`, `spotify_saved_tracks`, `spotify_followed_artists`,
`trakt_watched_movies`, `trakt_watched_shows`, `trakt_ratings`,
`bandcamp_collection`, `bandcamp_wishlist`.

### Columns

- `snake_case` everywhere
- Primary keys: `<entity>_id`
- Booleans: `is_`, `has_`, `did_` prefix
- Timestamps: `_at` suffix
- Dates: `_date` suffix

### Surrogate keys

Staging models generate surrogate keys via `dbt_utils.generate_surrogate_key([...])`.

| Model                           | Key column  | Source columns                             |
| ------------------------------- | ----------- | ------------------------------------------ |
| `stg_csv__bookbuddy`            | `book_id`   | `['title', 'author', 'isbn']`              |
| `stg_csv__letterboxd`           | `movie_id`  | `['watched_date', 'film_name']`            |
| `stg_csv__moviebuddy`           | `movie_id`  | `['title', 'release_year']`                |
| `stg_csv__musicbuddy`           | `album_id`  | `['title', 'artist', 'discogs_release_id']` |
| `stg_csv__goodreads`            | `book_id`   | Raw Goodreads string ID (stable source ID) |
| `stg_spotify__saved_albums`     | `album_id`  | Spotify `album_id` (stable source ID)      |
| `stg_spotify__saved_tracks`     | `track_id`  | Spotify `track_id` (stable source ID)      |
| `stg_spotify__followed_artists` | `artist_id` | Spotify `artist_id` (stable source ID)     |
| `stg_trakt__watched_movies`     | `movie_id`  | `['title', 'release_year']`                |
| `stg_trakt__watched_shows`      | `show_id`   | `['title', 'release_year']`                |
| `stg_trakt__ratings`            | `rating_id` | `['media_type', 'title', 'release_year']`  |

---

## Materialisation defaults (from `dbt_project.yml`)

| Layer          | Default |
| -------------- | ------- |
| `staging`      | `view`  |
| `intermediate` | `view`  |
| `mart`         | `table` |

Mart models are always `table` — they are the consumer-facing layer used by dashboards.
