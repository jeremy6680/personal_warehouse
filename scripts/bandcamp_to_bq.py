#!/usr/bin/env python3
"""
Fetches Bandcamp collection and wishlist items via Bandcamp's internal fan
collection API and writes them to BigQuery raw_personal as full-refresh loads.

Usage:
    python scripts/bandcamp_to_bq.py [--dry-run] [--table TABLE]

Options:
    --dry-run          Fetch data but skip BigQuery writes (safe to run anytime)
    --table TABLE      Sync a single table: collection | wishlist

Environment variables (see .env.example):
    BANDCAMP_IDENTITY_COOKIE
    BANDCAMP_FAN_ID
    GOOGLE_APPLICATION_CREDENTIALS   Path to GCP service account JSON
    BQ_PROJECT                       Default: personal-warehouse-495013
    BQ_DATASET                       Default: raw_personal
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

ENV_PATH = Path(__file__).parent.parent / ".env"


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue

        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


if load_dotenv:
    load_dotenv(ENV_PATH)
else:
    load_env_file(ENV_PATH)


BQ_PROJECT = os.getenv("BQ_PROJECT", "personal-warehouse-495013")
BQ_DATASET = os.getenv("BQ_DATASET", "raw_personal")
BANDCAMP_BASE_URL = "https://bandcamp.com/api/fancollection/1"
DEFAULT_COUNT = 1000


def _now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        sys.exit(f"[error] Missing required env var: {name}")
    return value


def _identity_cookie_value() -> str:
    value = _required_env("BANDCAMP_IDENTITY_COOKIE")
    if value.startswith("identity="):
        return value.removeprefix("identity=")
    return value


class BandcampClient:
    def __init__(self, identity_cookie: str):
        self.session = requests.Session()
        self.session.headers.update({
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "personal-warehouse/1.0",
        })
        self.session.cookies.set("identity", identity_cookie, domain=".bandcamp.com")

    def post(self, endpoint_name: str, json: dict[str, Any]) -> dict[str, Any]:
        response = self.session.post(
            f"{BANDCAMP_BASE_URL}/{endpoint_name}",
            json=json,
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()
        if payload.get("error"):
            message = payload.get("error_message") or payload["error"]
            raise RuntimeError(f"Bandcamp API error for {endpoint_name}: {message}")
        return payload


def _initial_older_than_token() -> str:
    return f"{int(time.time())}::a::"


def _coalesce(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None


def flatten_item(item: dict[str, Any], extracted_at: str) -> dict[str, Any]:
    title = _coalesce(item.get("album_title"), item.get("item_title"), item.get("title"))
    artist = _coalesce(item.get("band_name"), item.get("artist"), item.get("selling_band_name"))

    return {
        "item_id": item.get("item_id"),
        "item_type": item.get("item_type"),
        "tralbum_id": item.get("tralbum_id"),
        "tralbum_type": item.get("tralbum_type"),
        "title": title,
        "artist": artist,
        "item_url": item.get("item_url"),
        "art_url": item.get("art_url"),
        "token": item.get("token"),
        "added_at": _coalesce(
            item.get("added_at"),
            item.get("added"),
            item.get("purchased"),
            item.get("wishlisted"),
        ),
        "raw_json": json.dumps(item, sort_keys=True),
        "_extracted_at": extracted_at,
    }


def fetch_collection_page_set(
    client: BandcampClient,
    endpoint_name: str,
    fan_id: str,
    count: int,
    extracted_at: str,
) -> list[dict[str, Any]]:
    rows = []
    older_than_token = _initial_older_than_token()

    while True:
        payload = client.post(
            endpoint_name,
            json={
                "fan_id": int(fan_id),
                "older_than_token": older_than_token,
                "count": count,
            },
        )
        items = payload.get("items") or []
        rows.extend(flatten_item(item, extracted_at) for item in items)

        if not payload.get("more_available") or not items:
            break

        older_than_token = items[-1].get("token") or payload.get("last_token")
        if not older_than_token:
            raise RuntimeError(
                f"Bandcamp API returned more_available for {endpoint_name} "
                "without a continuation token."
            )

    return rows


def fetch_collection() -> list[dict[str, Any]]:
    client = BandcampClient(_identity_cookie_value())
    return fetch_collection_page_set(
        client=client,
        endpoint_name="collection_items",
        fan_id=_required_env("BANDCAMP_FAN_ID"),
        count=DEFAULT_COUNT,
        extracted_at=_now_utc(),
    )


def fetch_wishlist() -> list[dict[str, Any]]:
    client = BandcampClient(_identity_cookie_value())
    return fetch_collection_page_set(
        client=client,
        endpoint_name="wishlist_items",
        fan_id=_required_env("BANDCAMP_FAN_ID"),
        count=DEFAULT_COUNT,
        extracted_at=_now_utc(),
    )


def _schema():
    from google.cloud import bigquery

    return [
        bigquery.SchemaField("item_id", "INTEGER"),
        bigquery.SchemaField("item_type", "STRING"),
        bigquery.SchemaField("tralbum_id", "INTEGER"),
        bigquery.SchemaField("tralbum_type", "STRING"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("artist", "STRING"),
        bigquery.SchemaField("item_url", "STRING"),
        bigquery.SchemaField("art_url", "STRING"),
        bigquery.SchemaField("token", "STRING"),
        bigquery.SchemaField("added_at", "STRING"),
        bigquery.SchemaField("raw_json", "STRING"),
        bigquery.SchemaField("_extracted_at", "TIMESTAMP"),
    ]


def write_to_bq(
    client: Any,
    table_id: str,
    rows: list[dict[str, Any]],
    dry_run: bool = False,
) -> None:
    if dry_run:
        print(f"  [dry-run] Would write {len(rows)} rows to {table_id}")
        return

    from google.cloud import bigquery

    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=_schema(),
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    job = client.load_table_from_json(rows, table_id, job_config=job_config)
    job.result()
    print(f"  ✓ {len(rows)} rows written to {table_id}")


TABLES: dict[str, Any] = {
    "collection": fetch_collection,
    "wishlist": fetch_wishlist,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync Bandcamp fan collection data to BigQuery raw_personal."
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

    if args.dry_run:
        bq_client = None
    else:
        from google.cloud import bigquery
        bq_client = bigquery.Client(project=BQ_PROJECT)

    for table_name, fetch_fn in tables_to_run.items():
        bq_table = f"{BQ_PROJECT}.{BQ_DATASET}.bandcamp_{table_name}"
        print(f"Fetching bandcamp_{table_name}...")
        rows = fetch_fn()
        print(f"  → {len(rows)} rows fetched")
        write_to_bq(bq_client, bq_table, rows, dry_run=args.dry_run)

    print("\nDone. Run 'dbt build --select tag:bandcamp+' to rebuild Bandcamp models.")


if __name__ == "__main__":
    main()
