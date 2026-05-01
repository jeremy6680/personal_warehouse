# personal_warehouse

A personal analytics warehouse that centralises CSV exports from media-tracking apps into **BigQuery** and transforms them through a three-layer **dbt Core** pipeline.

---

## What this project does

Media-tracking apps (Goodreads, Letterboxd, BookBuddy, MovieBuddy, MusicBuddy) each store data in their own silo. This project:

1. Loads raw CSV exports into BigQuery (`raw_personal` dataset)
2. Cleans and standardises the data in the **staging layer**
3. Joins and enriches across sources in the **intermediate layer**
4. Produces dashboard-ready models in the **mart layer**

The end goal is a unified, queryable history of books read, movies watched, and music collected — with ratings, dates, and cross-domain analytics.

---

## Data sources

| Source | App | What it tracks |
|---|---|---|
| `goodreads` | Goodreads | Books read, ratings, shelves |
| `bookbuddy` | BookBuddy | Full book collection (read + wishlist) |
| `letterboxd` | Letterboxd | Movies watched, ratings, diary |
| `moviebuddy` | MovieBuddy | Full movie/TV collection (watched + wishlist) |
| `musicbuddy` | MusicBuddy | Music album collection via Discogs |

Raw CSV exports live in `data/` and are loaded into BigQuery manually (or via script). dbt never touches the raw files directly.

---

## Stack

| Concern | Tool |
|---|---|
| Transformation | dbt Core |
| Warehouse | BigQuery (`personal-warehouse-495013`) |
| Local query engine | DuckDB (for dev/portfolio) |
| Raw data | CSV exports loaded via `bq load` |
| Version control | Git |

---

## Quick start

```bash
# 1. Activate the virtual environment
source .venv/bin/activate        # from the repo root

# 2. Verify your dbt connection
dbt debug

# 3. Install dbt packages
dbt deps

# 4. Run all models
dbt run

# 5. Test all models
dbt test

# 6. Run and test together
dbt build
```

`profiles.yml` is never committed. Set it up at `~/.dbt/profiles.yml` using the BigQuery profile in [CLAUDE.md](CLAUDE.md#environment--profiles).

---

## Project layout

See [STRUCTURE.md](STRUCTURE.md) for a full map of the folder structure.  
See [CONTEXT.md](CONTEXT.md) for goals and design rationale.  
See [DECISIONS.md](DECISIONS.md) for architecture decision records.  
See [NEXT_STEPS.md](NEXT_STEPS.md) for current priorities.

---

## Model status

| Layer | Model | Status |
|---|---|---|
| Staging | `stg_csv__goodreads` | Done |
| Staging | `stg_csv__bookbuddy` | Pending |
| Staging | `stg_csv__letterboxd` | Pending |
| Staging | `stg_csv__moviebuddy` | Pending |
| Staging | `stg_csv__musicbuddy` | Pending |
| Intermediate | — | Not started |
| Mart | — | Not started |
