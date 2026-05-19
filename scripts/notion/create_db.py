#!/usr/bin/env python3
"""CLI script to create a Notion database as an inline child of a parent page.

Usage:
    python create_db.py --parent-page <page_id_or_url> --title <title> [--schema-file <path>]
    echo '{"properties": {...}}' | python create_db.py --parent-page <page_id_or_url> --title <title>
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from notion_wrapper import make_client, normalize_page_id, handle_api_error
from notion_client.errors import APIResponseError, RequestTimeoutError


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a Notion database as an inline child of a parent page."
    )
    parser.add_argument(
        "--parent-page",
        required=True,
        metavar="PAGE_ID_OR_URL",
        help="Parent page ID or Notion URL where the database will be created",
    )
    parser.add_argument(
        "--title",
        required=True,
        help="Database title",
    )
    parser.add_argument(
        "--schema-file",
        metavar="PATH",
        help="Path to JSON schema file (reads from stdin if omitted)",
    )
    return parser.parse_args()


def read_schema(schema_file: str | None) -> dict:
    """Read schema JSON from file or stdin."""
    if schema_file:
        with open(schema_file, "r", encoding="utf-8") as f:
            raw = f.read()
    else:
        raw = sys.stdin.read()

    data = json.loads(raw)
    return data.get("properties", data)


def main() -> None:
    args = parse_args()

    # Read and parse schema
    try:
        properties = read_schema(args.schema_file)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"Error: invalid JSON in schema: {exc}", file=sys.stderr)
        sys.exit(1)
    except OSError as exc:
        print(f"Error: cannot read schema file: {exc}", file=sys.stderr)
        sys.exit(1)

    if not properties:
        print("Warning: schema is empty — DB will have only the default 'Name' column", file=sys.stderr)

    # Initialize Notion client
    client = make_client()

    # Separate title property from other properties
    title_col_name = None
    non_title_props = {}
    for col_name, col_def in properties.items():
        if "title" in col_def:
            title_col_name = col_name
        else:
            non_title_props[col_name] = col_def

    parent_page_id = normalize_page_id(args.parent_page)

    try:
        # Step 1: Create the database (gets a default 'Name' title property)
        result = client.databases.create(
            parent={"type": "page_id", "page_id": parent_page_id},
            title=[{"type": "text", "text": {"content": args.title}}],
            is_inline=True,
        )

        db_id = result["id"]
        db_url = result.get("url", f"https://www.notion.so/{db_id.replace('-', '')}")

        # Step 2: Get data_source_id from response
        data_sources = result.get("data_sources", [])
        if not data_sources:
            print("Error: No data_sources returned from database creation", file=sys.stderr)
            sys.exit(1)
        ds_id = data_sources[0]["id"]

        # Step 3: Rename default 'Name' column if title column has a different name
        if title_col_name and title_col_name != "Name":
            client.data_sources.update(
                ds_id,
                properties={"Name": {"name": title_col_name}},
            )

        # Step 4: Add remaining (non-title) properties
        if non_title_props:
            client.data_sources.update(
                ds_id,
                properties=non_title_props,
            )

        print(f"DB created: {args.title}")
        print(f"- data_source_id: {ds_id}")
        print(f"- database_id: {db_id}")
        print(f"- URL: {db_url}")

    except (APIResponseError, RequestTimeoutError) as e:
        handle_api_error(e)


if __name__ == "__main__":
    main()
