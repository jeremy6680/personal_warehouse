# STRUCTURE.md — Folder and File Structure

This document explains what every folder and file in this project is for and how they relate to each other.

---

## Repository layout

```
personal_warehouse/               ← dbt project root (git repo)
│
├── data/                         ← Raw CSV exports (loaded into BigQuery externally)
│   ├── bookbuddy.csv             ← BookBuddy full library export
│   ├── goodreads.csv             ← Goodreads reading export
│   ├── letterboxd.csv            ← Letterboxd diary export
│   ├── moviebuddy.csv            ← MovieBuddy full collection export
│   └── musicbuddy.csv            ← MusicBuddy album collection export
│
├── models/
│   ├── staging/
│   │   └── csv/                  ← One sub-folder per source group
│   │       ├── _csv__sources.yml ← Source declarations + staging model docs (BigQuery raw_personal)
│   │       ├── stg_csv__goodreads.sql
│   │       ├── stg_csv__bookbuddy.sql
│   │       ├── stg_csv__letterboxd.sql
│   │       ├── stg_csv__moviebuddy.sql
│   │       └── stg_csv__musicbuddy.sql
│   │
│   ├── intermediate/
│   │   ├── _intermediate__models.yml  ← Intermediate model docs and tests (all domains)
│   │   ├── books/
│   │   │   └── int_books__unified.sql          ← BookBuddy + Goodreads union (3 cases)
│   │   ├── films/
│   │   │   └── int_movies__unified.sql         ← MovieBuddy + Letterboxd union (3 cases)
│   │   └── music/
│   │       └── int_music__collection.sql       ← MusicBuddy enriched with country
│   │
│   └── mart/
│       ├── _mart__models.yml             ← Mart model docs and tests (all domains)
│       ├── books/
│       │   └── mrt_books__collection.sql         ← Full book collection (read + unread)
│       ├── films/
│       │   └── mrt_movies__collection.sql        ← Full movie/TV collection (watched + wishlist)
│       ├── music/
│       │   └── mrt_music__collection.sql         ← Full album collection with country
│       └── cross_domain/
│           ├── mrt_media__summary.sql            ← Cross-domain counts, avg ratings, monthly pace
│           └── mrt_media__country_index.sql      ← One row per (country, domain, item)
│
├── seeds/                        ← Static reference CSVs managed by dbt seed
│   ├── _seeds.yml                ← Seed documentation and tests (all domains)
│   ├── books/
│   │   └── author_countries.csv  ← Author → country mapping
│   ├── films/
│   │   ├── director_countries.csv ← Director → country mapping
│   │   └── film_countries.csv    ← (title, release_year) → country fallback for Letterboxd-only rows
│   └── music/
│       └── artist_countries.csv  ← Artist → country mapping
│
├── analyses/                     ← Ad-hoc SQL (not materialised by dbt)
├── macros/                       ← Reusable Jinja macros
│   └── tests/                    ← Custom generic test macros
├── snapshots/                    ← SCD Type 2 snapshots
├── tests/                        ← Singular (one-off) data tests
├── target/                       ← Compiled artifacts (git-ignored)
├── logs/                         ← dbt logs (git-ignored)
│
├── dbt_project.yml               ← Project config (name, paths, materialisation defaults)
├── packages.yml                  ← dbt package dependencies (dbt_utils, dbt_expectations)
├── profiles.yml                  ← NOT committed — lives at ~/.dbt/profiles.yml
├── .gitignore
│
├── CLAUDE.md                     ← AI assistant instructions and code standards
├── CONTEXT.md                    ← Project goals and data source descriptions
├── DECISIONS.md                  ← Architecture decision records
├── NEXT_STEPS.md                 ← Current priorities
└── STRUCTURE.md                  ← This file
```

---

## Key distinctions

### `data/` vs `seeds/`

These folders look similar but serve opposite purposes:

|                 | `data/`                     | `seeds/`         |
| --------------- | --------------------------- | ---------------- |
| Who loads it?   | External (bq load, scripts) | dbt (`dbt seed`) |
| Source of truth | BigQuery / Postgres         | dbt repo         |
| Size            | Can be large                | Small only       |
| Changes         | From upstream app exports   | Manually edited  |
| Referenced via  | `source()`                  | `ref()`          |

All five media-tracking CSVs belong in `data/` because they come from external apps and could be replaced by an API integration in the future. The three `*_countries` seeds belong in `seeds/` because they are small, manually maintained reference tables that a data engineer would never ETL.

### `models/staging/csv/` — source grouping

The `csv/` sub-folder groups all CSV-backed sources together. If a future source (e.g., a Spotify API connector via Airbyte) is added, it would get its own sub-folder: `models/staging/spotify/`.

The `_csv__sources.yml` file declares the BigQuery tables in `raw_personal` that back these models, and also documents all five staging models in the same file.

### `models/intermediate/` — domain subfolders

Intermediate models are organised by domain (`books/`, `films/`, `music/`). All documentation lives in a single `_intermediate__models.yml` at the root of `models/intermediate/`.

This mirrors the `seeds/` folder structure and makes it easy to extend each domain independently.

---

## Naming conventions

### SQL files

- Staging: `stg_<source>__<entity>.sql`
- Intermediate: `int_<domain>__<description>.sql`
- Mart: `mrt_<domain>__<entity>.sql`

Double underscore `__` separates source/domain from entity.

### YAML files

- Sources + staging docs: `_<source>__sources.yml` (e.g., `_csv__sources.yml`)
- Intermediate docs: `_intermediate__models.yml`
- Mart docs: `_mart__models.yml`
- Seeds docs: `_seeds.yml`

### Columns

- `snake_case` everywhere
- Primary keys: `<entity>_id`
- Booleans: `is_`, `has_`, `did_` prefix
- Timestamps: `_at` suffix
- Dates: `_date` suffix

### Surrogate keys

Staging models generate surrogate keys via `dbt_utils.generate_surrogate_key([...])` on natural composite columns. The formula is kept stable so the same input always produces the same ID, enabling cross-source joins in intermediate.

| Model | Key column | Source columns |
|---|---|---|
| `stg_csv__bookbuddy` | `book_id` | `['title', 'author', 'isbn']` |
| `stg_csv__letterboxd` | `movie_id` | `['watched_date', 'film_name']` |
| `stg_csv__moviebuddy` | `movie_id` | `['title', 'release_year']` |
| `stg_csv__musicbuddy` | `album_id` | `['title', 'artist', 'discogs_release_id']` |
| `stg_csv__goodreads` | `book_id` | Raw Goodreads string ID (stable source ID) |

---

## Materialisation defaults (from `dbt_project.yml`)

| Layer          | Default |
| -------------- | ------- |
| `staging`      | `view`  |
| `intermediate` | `view`  |
| `mart`         | `table` |

Mart models are always `table` — they are the consumer-facing layer used by dashboards.
