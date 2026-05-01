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
│   │       ├── _csv__sources.yml ← Source declarations (BigQuery raw_personal dataset)
│   │       └── stg_csv__goodreads.sql
│   ├── intermediate/             ← (empty — not yet built)
│   └── mart/                     ← (empty — not yet built)
│
├── analyses/                     ← Ad-hoc SQL (not materialised by dbt)
├── macros/                       ← Reusable Jinja macros
│   └── tests/                    ← Custom generic test macros
├── seeds/                        ← Static reference CSVs managed by dbt seed
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

| | `data/` | `seeds/` |
|---|---|---|
| Who loads it? | External (bq load, scripts) | dbt (`dbt seed`) |
| Source of truth | BigQuery / Postgres | dbt repo |
| Size | Can be large | Small only |
| Changes | From upstream app exports | Manually edited |
| Referenced via | `source()` | `ref()` |

All five media-tracking CSVs belong in `data/` because they come from external apps and could be replaced by an API integration in the future.

### `models/staging/csv/` — source grouping

The `csv/` sub-folder groups all CSV-backed sources together. If a future source (e.g., a Spotify API connector via Airbyte) is added, it would get its own sub-folder: `models/staging/spotify/`.

The `_csv__sources.yml` file declares the BigQuery tables in `raw_personal` that back these models.

---

## Naming conventions

### SQL files
- Staging: `stg_<source>__<entity>.sql`
- Intermediate: `int_<domain>__<description>.sql`
- Mart: `mrt_<domain>__<entity>.sql`

Double underscore `__` separates source/domain from entity.

### YAML files
- Sources: `_<source>__sources.yml`
- Model docs: `_<layer>__models.yml` (or grouped by domain)

### Columns
- `snake_case` everywhere
- Primary keys: `<entity>_id`
- Booleans: `is_`, `has_`, `did_` prefix
- Timestamps: `_at` suffix
- Dates: `_date` suffix

---

## Materialisation defaults (from `dbt_project.yml`)

| Layer | Default |
|---|---|
| `staging` | `view` |
| `intermediate` | `ephemeral` |
| `mart` | `table` |

Mart models are always `table` — they are the consumer-facing layer used by dashboards.
