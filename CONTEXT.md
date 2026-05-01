# CONTEXT.md — Project Overview and Goals

## Why this project exists

Every media-tracking app is a silo. Goodreads knows what you read; Letterboxd knows what you watched; BookBuddy and MovieBuddy know what's on your shelves. None of them talk to each other, and none of them let you ask cross-domain questions like:

- "What genres do I rate highest across books and films?"
- "How many books/movies did I finish per month this year?"
- "Which authors or directors appear most in my collection?"

This project is the answer: a single analytics warehouse that owns all that data and makes it queryable.

It also serves as a **portfolio project** demonstrating dbt analytics engineering patterns (three-layer architecture, source/ref hygiene, YAML documentation, testing) on a real, personally-meaningful dataset.

---

## Data sources

### Goodreads (`goodreads.csv`)
- Exported from [goodreads.com](https://www.goodreads.com) via the account export feature
- Contains: books read, personal ratings (1–5), shelves (`read` / `to-read` / `currently-reading`), dates added and read
- Primary use: reading history and ratings

### BookBuddy (`bookbuddy.csv`)
- Exported from the BookBuddy iOS app
- Contains: full book collection including unread books, richer metadata (genre, category, publisher, ISBN, tags, status, condition)
- Complements Goodreads: broader collection scope, richer metadata, but less precise on reading dates

### Letterboxd (`letterboxd.csv`)
- Exported from [letterboxd.com](https://letterboxd.com) via the account export feature
- Contains: movies watched with diary dates and personal ratings (0.5–5 stars)
- Primary use: movie watching history and ratings

### MovieBuddy (`moviebuddy.csv`)
- Exported from the MovieBuddy iOS app
- Contains: full movie and TV collection including "Not Watched" status, rich metadata (director, cast, TMDB ID, genres, runtime, film rating)
- Complements Letterboxd: covers wishlist/collection, richer metadata

### MusicBuddy (`musicbuddy.csv`)
- Exported from the MusicBuddy iOS app (backed by Discogs)
- Contains: music album collection — artist, genre, style, tracks, format, Discogs release ID
- Unique domain: no direct equivalent app for rating/diary, collection-oriented

---

## Goals

### Phase 1 — Staging (current focus)
- Clean and standardise every source CSV into a well-typed, consistently-named staging model
- No joins, no business logic — purely rename, cast, deduplicate

### Phase 2 — Intermediate
- Unified book model merging Goodreads reading history with BookBuddy collection metadata
- Unified movie model merging Letterboxd diary with MovieBuddy collection metadata

### Phase 3 — Mart
- `mrt_books__reading_history` — books finished, with rating, genre, dates
- `mrt_movies__watching_history` — movies watched, with rating, director, genre
- `mrt_music__collection` — full album collection with genre and style breakdown
- `mrt_media__cross_domain_summary` — cross-domain stats: items per domain, avg rating, monthly pace

### Long-term
- Visualise in a BI tool (Looker Studio or Metabase) connected to BigQuery mart tables
- Schedule automatic CSV refreshes and incremental loads

---

## Target audience

Personal use only. This is a solo project — no multi-user concerns, no PII beyond self-reported data.
