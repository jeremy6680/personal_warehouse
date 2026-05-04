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
│ │ │ ├── \_csv**sources.yml ← Source declarations + staging model docs
│ │ │ ├── \_csv**docs.md ← Docs blocks for CSV staging models
│ │ │ ├── stg_csv**goodreads.sql
│ │ │ ├── stg_csv**bookbuddy.sql
│ │ │ ├── stg_csv**letterboxd.sql
│ │ │ ├── stg_csv**moviebuddy.sql
│ │ │ └── stg_csv**musicbuddy.sql
│ │ └── spotify/ ← Spotify API source (raw_personal dataset)
│ │ ├── \_spotify**sources.yml
│ │ ├── stg_spotify**saved_albums.sql
│ │ ├── stg_spotify**saved_tracks.sql
│ │ └── stg_spotify**followed_artists.sql
│ │
│ ├── intermediate/
│ │ ├── \_intermediate**models.yml ← Intermediate model docs and tests (all domains)
│ │ ├── books/
│ │ │ └── int_books**unified.sql
│ │ ├── films/
│ │ │ └── int_movies**unified.sql
│ │ └── music/
│ │ ├── int_music**collection.sql ← Orphan — superseded by int_music__unified
│ │ └── int_music**unified.sql ← MusicBuddy + Spotify union
│ │
│ └── mart/
│ ├── \_mart**models.yml
│ ├── books/
│ │ ├── mrt_books**reading_history.sql
│ │ └── mrt_books**collection.sql
│ ├── films/
│ │ ├── mrt_movies**watching_history.sql
│ │ └── mrt_movies**collection.sql
│ ├── music/
│ │ └── mrt_music**collection.sql ← MusicBuddy + Spotify albums
│ └── shared/
│ ├── mrt_media**summary.sql
│ └── mrt_media**country_index.sql
│
├── seeds/ ← Static reference CSVs managed by dbt seed
│ ├── \_seeds.yml ← Seed documentation and tests (all domains)
│ ├── books/
│ │ └── author_countries.csv
│ ├── films/
│ │ ├── director_countries.csv
│ │ └── film_countries.csv
│ └── music/
│ └── artist_countries.csv
│
├── scripts/
│ ├── bq_load.sh ← Loads CSV files into raw_personal via bq load
│ └── spotify_to_bq.py ← Fetches Spotify data via API → writes to raw_personal
│
├── dags/
│ └── spotify_ingest.py ← Airflow DAG: spotify_to_bq.py → dbt build [planned]
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
| `raw_personal`       | Tables brutes de toutes les sources : CSV exports (`bookbuddy`, `goodreads`, etc.) + tables API (`spotify_*`) | `bq load`, scripts Python |
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

### `models/staging/csv/` vs `models/staging/spotify/`

Each source group gets its own sub-folder and its own `_<source>__sources.yml`. Both point to
`raw_personal` as their BigQuery dataset — the sub-folder separation is a dbt organisation
convention, not a warehouse-level distinction.

### `scripts/` vs `dags/`

- `scripts/` — standalone Python/shell scripts that can be run directly (`python spotify_to_bq.py`)
- `dags/` — Airflow DAG definitions that orchestrate those scripts + dbt runs on a schedule

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

### BigQuery raw tables — Spotify prefix

Spotify tables in `raw_personal` use a `spotify_` prefix to avoid collisions with CSV-backed tables:
`spotify_saved_albums`, `spotify_saved_tracks`, `spotify_followed_artists`.

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
| `stg_csv__bookbuddy`            | `book_id`   | `['title', 'author']`                      |
| `stg_csv__letterboxd`           | `movie_id`  | `['watched_date', 'film_name']`            |
| `stg_csv__moviebuddy`           | `movie_id`  | `['title', 'release_year']`                |
| `stg_csv__musicbuddy`           | `album_id`  | `['title', 'artist']`                      |
| `stg_csv__goodreads`            | `book_id`   | Raw Goodreads string ID (stable source ID) |
| `stg_spotify__saved_albums`     | `album_id`  | Spotify `album_id` (stable source ID)      |
| `stg_spotify__saved_tracks`     | `track_id`  | Spotify `track_id` (stable source ID)      |
| `stg_spotify__followed_artists` | `artist_id` | Spotify `artist_id` (stable source ID)     |

---

## Materialisation defaults (from `dbt_project.yml`)

| Layer          | Default |
| -------------- | ------- |
| `staging`      | `view`  |
| `intermediate` | `view`  |
| `mart`         | `table` |

Mart models are always `table` — they are the consumer-facing layer used by dashboards.
