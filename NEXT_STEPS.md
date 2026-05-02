# NEXT_STEPS.md — Current Priorities

Work items are listed in recommended order. Complete items are checked off. Add new items at the bottom of the relevant section.

---

## Staging layer

### Done

- [x] `stg_csv__goodreads` — basic cast and rename

### Done

- [x] Expand `stg_csv__goodreads` — columns added as needed

### Done

- [x] `stg_csv__bookbuddy` — title, author, genre, category, status, rating, `is_favorite`, ISBN, tags, `date_started`, `date_finished`
- [x] `stg_csv__letterboxd` — `watched_date`, `film_name`, `release_year`, `letterboxd_uri`, `rating`
- [x] `stg_csv__moviebuddy` — title, `content_type`, `release_year`, `status`, `rating`, `is_favorite`, directors, genres, `runtime_minutes`, `tmdb_id`, `date_finished`
- [x] `stg_csv__musicbuddy` — title, artist, genres, styles, `release_year`, format, `discogs_release_id`, `rating`
- [x] Add YAML documentation and tests for all staging models in `_csv__sources.yml`
- [x] Load all five CSVs into BigQuery `raw_personal` dataset via `bq load`

---

## Intermediate layer

- [ ] `int_books__collection_with_history` — merge BookBuddy collection with Goodreads reading history (join on ISBN; fallback to title + author)
- [ ] `int_movies__collection_with_diary` — merge MovieBuddy collection with Letterboxd diary (join on TMDB ID; fallback to title + year)

---

## Mart layer

- [ ] `mrt_books__reading_history` — finished books with rating, genre, dates (from intermediate books model)
- [ ] `mrt_books__collection` — full book collection (read + unread) with metadata
- [ ] `mrt_movies__watching_history` — movies watched with rating, director, genre, watch date
- [ ] `mrt_movies__collection` — full movie/TV collection (watched + wishlist)
- [ ] `mrt_music__collection` — full album collection with genre, style, artist
- [ ] `mrt_media__summary` — cross-domain aggregate: counts, avg ratings, monthly pace per domain

---

## Infrastructure and tooling

- [ ] Set up `packages.yml` with `dbt_utils` and `dbt_expectations`
- [ ] Run `dbt deps` to install packages
- [ ] Set up `.sqlfluff` for SQL linting
- [ ] Confirm `profiles.yml` is configured and `dbt debug` passes against BigQuery
- [ ] Add `bq load` commands or a shell script to reload CSVs into `raw_personal`

---

## Future / nice to have

- [ ] Looker Studio or Metabase dashboard connected to mart tables
- [ ] Schedule CSV refresh + `dbt build` (cron or Cloud Scheduler)
- [ ] Explore Spotify API via Airbyte to replace/supplement MusicBuddy CSV
