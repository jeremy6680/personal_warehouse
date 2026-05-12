import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "bandcamp_to_bq.py"


def load_module():
    spec = importlib.util.spec_from_file_location("bandcamp_to_bq", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BandcampToBqTest(unittest.TestCase):
    def test_bandcamp_item_is_flattened_with_raw_json(self):
        module = load_module()

        row = module.flatten_item(
            {
                "item_id": 123,
                "item_type": "a",
                "album_title": "Blue Rev",
                "band_name": "Alvvays",
                "item_url": "https://alvvays.bandcamp.com/album/blue-rev",
                "token": "1700000000:123:a::",
                "tralbum_id": 456,
                "tralbum_type": "a",
            },
            extracted_at="2026-05-12T12:00:00+00:00",
        )

        self.assertEqual(row["item_id"], 123)
        self.assertEqual(row["item_type"], "a")
        self.assertEqual(row["title"], "Blue Rev")
        self.assertEqual(row["artist"], "Alvvays")
        self.assertEqual(
            row["item_url"],
            "https://alvvays.bandcamp.com/album/blue-rev",
        )
        self.assertEqual(row["token"], "1700000000:123:a::")
        self.assertEqual(row["tralbum_id"], 456)
        self.assertEqual(row["tralbum_type"], "a")
        self.assertEqual(row["_extracted_at"], "2026-05-12T12:00:00+00:00")
        self.assertIn('"album_title": "Blue Rev"', row["raw_json"])

    def test_paginated_fetch_uses_last_item_token_when_more_items_exist(self):
        module = load_module()
        client = Mock()
        client.post.side_effect = [
            {
                "items": [
                    {"album_title": "First", "band_name": "Artist", "token": "token-1"},
                    {"album_title": "Second", "band_name": "Artist", "token": "token-2"},
                ],
                "more_available": True,
                "last_token": "wrong-token-for-large-count",
            },
            {
                "items": [
                    {"album_title": "Third", "band_name": "Artist", "token": "token-3"}
                ],
                "more_available": False,
                "last_token": "token-3",
            },
        ]

        rows = module.fetch_collection_page_set(
            client=client,
            endpoint_name="collection_items",
            fan_id="42",
            count=1000,
            extracted_at="2026-05-12T12:00:00+00:00",
        )

        self.assertEqual([row["title"] for row in rows], ["First", "Second", "Third"])
        self.assertEqual(
            client.post.call_args_list[1].kwargs["json"]["older_than_token"],
            "token-2",
        )

    def test_fallback_dotenv_loader_sets_missing_environment_values(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            env_file = Path(tmpdir) / ".env"
            env_file.write_text(
                "BANDCAMP_IDENTITY_COOKIE=identity-value\n"
                "BANDCAMP_FAN_ID=12345\n",
                encoding="utf-8",
            )

            old_cookie = os.environ.pop("BANDCAMP_IDENTITY_COOKIE", None)
            old_fan_id = os.environ.pop("BANDCAMP_FAN_ID", None)
            try:
                module.load_env_file(env_file)
                self.assertEqual(os.environ["BANDCAMP_IDENTITY_COOKIE"], "identity-value")
                self.assertEqual(os.environ["BANDCAMP_FAN_ID"], "12345")
            finally:
                os.environ.pop("BANDCAMP_IDENTITY_COOKIE", None)
                os.environ.pop("BANDCAMP_FAN_ID", None)
                if old_cookie is not None:
                    os.environ["BANDCAMP_IDENTITY_COOKIE"] = old_cookie
                if old_fan_id is not None:
                    os.environ["BANDCAMP_FAN_ID"] = old_fan_id


if __name__ == "__main__":
    unittest.main()
