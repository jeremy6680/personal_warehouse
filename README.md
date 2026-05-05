# personal_warehouse

A personal analytics warehouse that centralises CSV exports from media-tracking apps into **BigQuery** and transforms them through a three-layer **dbt Core** pipeline.

---

## What this project does

Media-tracking apps (Goodreads, Letterboxd, BookBuddy, MovieBuddy, MusicBuddy) each store data in their own silo. This project:

1. Loads raw CSV exports into BigQuery (`raw_personal` dataset)
2. Cleans and standardises the data in the **staging layer**
3. Joins and enriches across sources in the **intermediate layer**
4. Produces dashboard-ready models in the **mart layer**
5. Exposes the results in **[Evidence.dev](https://mediatheque.jeremymarchandeau.com)** — static dashboard deployed on Netlify

The end goal is a unified, queryable history of books read, movies watched, and music collected — with ratings, dates, and cross-domain analytics.

👉 **Dashboard:** https://mediatheque.jeremymarchandeau.com  
👉 **Dashboard repo:** https://github.com/jeremy6680/personal-warehouse-dashboard

---

## Data sources

| Source | App | Ingestion | What it tracks |
|---|---|---|---|
| `goodreads` | Goodreads | CSV → `bq load` | Books read, ratings, shelves |
| `bookbuddy` | BookBuddy | CSV → `bq load` | Full book collection (read + wishlist) |
| `letterboxd` | Letterboxd | CSV → `bq load` | Movies watched, ratings, diary |
| `moviebuddy` | MovieBuddy | CSV → `bq load` | Full movie/TV collection (watched + wishlist) |
| `musicbuddy` | MusicBuddy | CSV → `bq load` | Music album collection via Discogs |
| `spotify` | Spotify | API → `scripts/spotify_to_bq.py` | Saved albums, saved tracks, followed artists |

CSV exports live in `data/` and are loaded into BigQuery via `bq load`. Spotify data is fetched via the Spotify Web API using `scripts/spotify_to_bq.py`.

---

## Stack

| Concern | Tool |
|---|---|
| Transformation | dbt Core |
| Warehouse | BigQuery (`personal-warehouse-495013`) |
| Local query engine | DuckDB (for dev/portfolio) |
| Raw data | CSV exports (`bq load`) + Spotify API (`scripts/spotify_to_bq.py`) |
| Visualisation | Evidence.dev (static site) deployed on Netlify |
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

# 4. Load seeds (reference CSVs managed by dbt)
dbt seed

# 5. Run all models
dbt run

# 6. Test all models
dbt test

# 7. Run and test together
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
| Staging | `stg_csv__bookbuddy` | Done |
| Staging | `stg_csv__letterboxd` | Done |
| Staging | `stg_csv__moviebuddy` | Done |
| Staging | `stg_csv__musicbuddy` | Done |
| Seeds | `author_countries` | Done |
| Seeds | `director_countries` | Done |
| Seeds | `artist_countries` | Done |
| Seeds | `country_iso_codes` | Done |
| Intermediate | `int_books__unified` | Done |
| Intermediate | `int_movies__unified` | Done |
| Intermediate | `int_music__unified` | Done |
| Staging | `stg_spotify__saved_albums` | Done |
| Staging | `stg_spotify__saved_tracks` | Done |
| Staging | `stg_spotify__followed_artists` | Done |
| Mart | `mrt_books__collection` | Done |
| Mart | `mrt_movies__collection` | Done |
| Mart | `mrt_music__collection` | Done |
| Mart | `mrt_media__summary` | Done |
| Mart | `mrt_media__country_index` | Done |
