#!/usr/bin/env python3
"""
Fetches Trakt watched movies, watched shows, and ratings via the Trakt API v2
and writes them to BigQuery raw_personal as full-refresh loads.

Usage:
    python scripts/trakt_to_bq.py [--dry-run] [--table TABLE]

Options:
    --dry-run          Fetch data but skip BigQuery writes (safe to run anytime)
    --table TABLE      Sync a single table: watched_movies | watched_shows | ratings

Environment variables (see .env.example):
    TRAKT_API_KEY
    TRAKT_USERNAME
    GOOGLE_APPLICATION_CREDENTIALS   Path to GCP service account JSON
    BQ_PROJECT                       Default: personal-warehouse-495013
    BQ_DATASET                       Default: raw_personal
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv(Path(__file__).parent.parent / ".env")


BQ_PROJECT = os.getenv("BQ_PROJECT", "personal-warehouse-495013")
BQ_DATASET = os.getenv("BQ_DATASET", "raw_personal")
TRAKT_BASE_URL = "https://api.trakt.tv"
TRAKT_API_VERSION = "2"


def _now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        sys.exit(f"[error] Missing required env var: {name}")
    return value


def _headers() -> dict[str, str]:
    return {
        "Content-Type": "application/json",
        "trakt-api-version": TRAKT_API_VERSION,
        "trakt-api-key": _required_env("TRAKT_API_KEY"),
    }


def _get(path: str, params: dict[str, str] | None = None) -> Any:
    response = requests.get(
        f"{TRAKT_BASE_URL}{path}",
        headers=_headers(),
        params=params,
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def _ids(item: dict[str, Any]) -> dict[str, Any]:
    ids = item.get("ids") or {}
    return {
        "trakt_id": ids.get("trakt"),
        "slug": ids.get("slug"),
        "imdb_id": ids.get("imdb"),
        "tmdb_id": ids.get("tmdb"),
    }


def _json_list(value: Any) -> str:
    return json.dumps(value or [])


def fetch_watched_movies() -> list[dict[str, Any]]:
    username = _required_env("TRAKT_USERNAME")
    extracted_at = _now_utc()
    rows = []

    payload = _get(
        f"/users/{username}/watched/movies",
        params={"extended": "full"},
    )

    for item in payload:
        movie = item.get("movie") or {}
        ids = _ids(movie)
        rows.append({
            "trakt_movie_id": ids["trakt_id"],
            "slug": ids["slug"],
            "imdb_id": ids["imdb_id"],
            "tmdb_id": ids["tmdb_id"],
            "title": movie.get("title"),
            "release_year": movie.get("year"),
            "plays": item.get("plays"),
            "last_watched_at": item.get("last_watched_at"),
            "last_updated_at": item.get("last_updated_at"),
            "genres": _json_list(movie.get("genres")),
            "runtime_minutes": movie.get("runtime"),
            "country": movie.get("country"),
            "_extracted_at": extracted_at,
        })

    return rows


def fetch_watched_shows() -> list[dict[str, Any]]:
    username = _required_env("TRAKT_USERNAME")
    extracted_at = _now_utc()
    rows = []

    payload = _get(
        f"/users/{username}/watched/shows",
        params={"extended": "full", "hidden": "false"},
    )

    for item in payload:
        show = item.get("show") or {}
        ids = _ids(show)
        rows.append({
            "trakt_show_id": ids["trakt_id"],
            "slug": ids["slug"],
            "imdb_id": ids["imdb_id"],
            "tmdb_id": ids["tmdb_id"],
            "title": show.get("title"),
            "release_year": show.get("year"),
            "plays": item.get("plays"),
            "last_watched_at": item.get("last_watched_at"),
            "last_updated_at": item.get("last_updated_at"),
            "genres": _json_list(show.get("genres")),
            "runtime_minutes": show.get("runtime"),
            "status": show.get("status"),
            "network": show.get("network"),
            "country": show.get("country"),
            "_extracted_at": extracted_at,
        })

    return rows


def _rating_rows(media_type: str, extracted_at: str) -> list[dict[str, Any]]:
    username = _required_env("TRAKT_USERNAME")
    payload = _get(
        f"/users/{username}/ratings/{media_type}",
        params={"extended": "full"},
    )

    rows = []
    object_key = "movie" if media_type == "movies" else "show"
    singular_type = "movie" if media_type == "movies" else "show"

    for item in payload:
        media = item.get(object_key) or {}
        ids = _ids(media)
        rating_raw = item.get("rating")
        rows.append({
            "media_type": singular_type,
            "trakt_id": ids["trakt_id"],
            "slug": ids["slug"],
            "imdb_id": ids["imdb_id"],
            "tmdb_id": ids["tmdb_id"],
            "title": media.get("title"),
            "release_year": media.get("year"),
            "rating_raw": rating_raw,
            "rating": rating_raw / 2 if rating_raw is not None else None,
            "rated_at": item.get("rated_at"),
            "genres": _json_list(media.get("genres")),
            "runtime_minutes": media.get("runtime"),
            "country": media.get("country"),
            "_extracted_at": extracted_at,
        })

    return rows


def fetch_ratings() -> list[dict[str, Any]]:
    extracted_at = _now_utc()
    return _rating_rows("movies", extracted_at) + _rating_rows("shows", extracted_at)


SCHEMAS: dict[str, list[bigquery.SchemaField]] = {
    "watched_movies": [
        bigquery.SchemaField("trakt_movie_id", "INTEGER"),
        bigquery.SchemaField("slug", "STRING"),
        bigquery.SchemaField("imdb_id", "STRING"),
        bigquery.SchemaField("tmdb_id", "INTEGER"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("release_year", "INTEGER"),
        bigquery.SchemaField("plays", "INTEGER"),
        bigquery.SchemaField("last_watched_at", "TIMESTAMP"),
        bigquery.SchemaField("last_updated_at", "TIMESTAMP"),
        bigquery.SchemaField("genres", "STRING"),
        bigquery.SchemaField("runtime_minutes", "INTEGER"),
        bigquery.SchemaField("country", "STRING"),
        bigquery.SchemaField("_extracted_at", "TIMESTAMP"),
    ],
    "watched_shows": [
        bigquery.SchemaField("trakt_show_id", "INTEGER"),
        bigquery.SchemaField("slug", "STRING"),
        bigquery.SchemaField("imdb_id", "STRING"),
        bigquery.SchemaField("tmdb_id", "INTEGER"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("release_year", "INTEGER"),
        bigquery.SchemaField("plays", "INTEGER"),
        bigquery.SchemaField("last_watched_at", "TIMESTAMP"),
        bigquery.SchemaField("last_updated_at", "TIMESTAMP"),
        bigquery.SchemaField("genres", "STRING"),
        bigquery.SchemaField("runtime_minutes", "INTEGER"),
        bigquery.SchemaField("status", "STRING"),
        bigquery.SchemaField("network", "STRING"),
        bigquery.SchemaField("country", "STRING"),
        bigquery.SchemaField("_extracted_at", "TIMESTAMP"),
    ],
    "ratings": [
        bigquery.SchemaField("media_type", "STRING"),
        bigquery.SchemaField("trakt_id", "INTEGER"),
        bigquery.SchemaField("slug", "STRING"),
        bigquery.SchemaField("imdb_id", "STRING"),
        bigquery.SchemaField("tmdb_id", "INTEGER"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("release_year", "INTEGER"),
        bigquery.SchemaField("rating_raw", "INTEGER"),
        bigquery.SchemaField("rating", "FLOAT"),
        bigquery.SchemaField("rated_at", "TIMESTAMP"),
        bigquery.SchemaField("genres", "STRING"),
        bigquery.SchemaField("runtime_minutes", "INTEGER"),
        bigquery.SchemaField("country", "STRING"),
        bigquery.SchemaField("_extracted_at", "TIMESTAMP"),
    ],
}


def write_to_bq(
    client: bigquery.Client,
    table_name: str,
    table_id: str,
    rows: list[dict[str, Any]],
    dry_run: bool = False,
) -> None:
    if dry_run:
        print(f"  [dry-run] Would write {len(rows)} rows to {table_id}")
        return

    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=SCHEMAS[table_name],
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    job = client.load_table_from_json(rows, table_id, job_config=job_config)
    job.result()
    print(f"  ✓ {len(rows)} rows written to {table_id}")


TABLES: dict[str, Any] = {
    "watched_movies": fetch_watched_movies,
    "watched_shows": fetch_watched_shows,
    "ratings": fetch_ratings,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync Trakt data to BigQuery raw_personal."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch data but skip BigQuery writes.",
    )
    parser.add_argument(
        "--table",
        choices=list(TABLES.keys()),
        help="Sync a single table only.",
    )
    args = parser.parse_args()

    tables_to_run = {args.table: TABLES[args.table]} if args.table else TABLES
    bq_client = None if args.dry_run else bigquery.Client(project=BQ_PROJECT)

    for table_name, fetch_fn in tables_to_run.items():
        bq_table = f"{BQ_PROJECT}.{BQ_DATASET}.trakt_{table_name}"
        print(f"Fetching trakt_{table_name}...")
        rows = fetch_fn()
        print(f"  → {len(rows)} rows fetched")
        write_to_bq(bq_client, table_name, bq_table, rows, dry_run=args.dry_run)

    print("\nDone. Run 'dbt build --select tag:trakt+' to rebuild Trakt models.")


if __name__ == "__main__":
    main()
