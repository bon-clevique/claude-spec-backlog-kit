#!/usr/bin/env python3
"""CLI script to edit Notion databases: add rows, modify properties, update rows."""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from notion_wrapper import make_client, normalize_page_id, handle_api_error
from notion_client.errors import APIResponseError, RequestTimeoutError


def _get_schema(client, ds_id: str) -> dict:
    """Retrieve data_source and return property name → type mapping."""
    ds = client.data_sources.retrieve(ds_id)
    properties = ds.get("properties", {})
    return {name: prop.get("type", "") for name, prop in properties.items()}


def _convert_value(prop_type: str, value) -> dict:
    """Convert a simplified value to Notion property format based on prop_type."""
    if prop_type == "title":
        return {"title": [{"text": {"content": str(value)}}]}
    elif prop_type == "rich_text":
        return {"rich_text": [{"text": {"content": str(value)}}]}
    elif prop_type == "number":
        return {"number": value}
    elif prop_type == "checkbox":
        return {"checkbox": bool(value)}
    elif prop_type == "select":
        return {"select": {"name": str(value)}}
    elif prop_type == "date":
        return {"date": {"start": str(value)}}
    elif prop_type == "url":
        return {"url": str(value)}
    elif prop_type == "email":
        return {"email": str(value)}
    elif prop_type == "phone_number":
        return {"phone_number": str(value)}
    elif prop_type == "multi_select":
        if isinstance(value, list):
            return {"multi_select": [{"name": str(v)} for v in value]}
        return {"multi_select": [{"name": str(value)}]}
    else:
        # Fallback: attempt rich_text for unknown types
        return {"rich_text": [{"text": {"content": str(value)}}]}


def _read_json_input(data_file: str | None) -> object:
    """Read JSON from a file or stdin."""
    try:
        if data_file:
            with open(data_file, "r", encoding="utf-8") as f:
                return json.load(f)
        else:
            return json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON input: {exc}", file=sys.stderr)
        sys.exit(1)
    except OSError as exc:
        print(f"Error: cannot read file: {exc}", file=sys.stderr)
        sys.exit(1)


def _convert_row(row: dict, schema: dict) -> dict:
    """Convert a simplified row dict to Notion properties format using schema."""
    props = {}
    for name, value in row.items():
        prop_type = schema.get(name)
        if prop_type is None:
            print(f"Warning: property '{name}' not found in schema, skipping", file=sys.stderr)
            continue
        props[name] = _convert_value(prop_type, value)
    return props


def _get_title_value(row: dict, schema: dict) -> str:
    """Extract the title property value from a row dict."""
    for name, prop_type in schema.items():
        if prop_type == "title" and name in row:
            return str(row[name])
    # Fallback: return first value or empty string
    return next(iter(row.values()), "") if row else ""


def cmd_add_row(args):
    """Add a single row to a Notion database."""
    client = make_client()
    ds_id = args.ds

    try:
        schema = _get_schema(client, ds_id)
        row = _read_json_input(args.data_file)
        if not isinstance(row, dict):
            print("Error: row data must be a JSON object", file=sys.stderr)
            sys.exit(1)

        title_value = _get_title_value(row, schema)
        converted = _convert_row(row, schema)

        result = client.pages.create(
            parent={"data_source_id": ds_id},
            properties=converted,
        )
        page_id = result.get("id", "")
        print(f"Row added: {title_value} (page_id: {page_id})")

    except (APIResponseError, RequestTimeoutError) as e:
        handle_api_error(e)


def cmd_add_rows(args):
    """Add multiple rows to a Notion database."""
    client = make_client()
    ds_id = args.ds

    try:
        schema = _get_schema(client, ds_id)
        rows = _read_json_input(args.data_file)
        if not isinstance(rows, list):
            print("Error: rows data must be a JSON array", file=sys.stderr)
            sys.exit(1)

        count = 0
        failed = 0
        for i, row in enumerate(rows):
            if not isinstance(row, dict):
                print(f"Warning: skipping non-object item at index {i}", file=sys.stderr)
                failed += 1
                continue
            converted = _convert_row(row, schema)
            try:
                client.pages.create(
                    parent={"data_source_id": ds_id},
                    properties=converted,
                )
                count += 1
            except (APIResponseError, RequestTimeoutError) as e:
                print(f"Warning: failed to create row at index {i}: {e}", file=sys.stderr)
                failed += 1

        print(f"{count} rows added to {ds_id}")
        if failed:
            print(f"{failed} rows failed", file=sys.stderr)

    except (APIResponseError, RequestTimeoutError) as e:
        handle_api_error(e)


def cmd_add_property(args):
    """Add a property to a Notion database."""
    client = make_client()
    ds_id = args.ds
    name = args.name
    prop_type = args.type

    supported_types = {
        "rich_text", "number", "select", "multi_select",
        "checkbox", "date", "url", "email", "phone_number",
    }
    if prop_type not in supported_types:
        print(f"Error: unsupported type '{prop_type}'. Supported: {', '.join(sorted(supported_types))}", file=sys.stderr)
        sys.exit(1)

    try:
        prop_def: dict = {prop_type: {}}

        if args.options and prop_type in ("select", "multi_select"):
            try:
                options = json.loads(args.options)
            except json.JSONDecodeError as exc:
                print(f"Error: --options is not valid JSON: {exc}", file=sys.stderr)
                sys.exit(1)
            prop_def[prop_type] = {"options": options}

        client.data_sources.update(ds_id, properties={name: prop_def})
        print(f"Property added: {name} ({prop_type})")

    except (APIResponseError, RequestTimeoutError) as e:
        handle_api_error(e)


def cmd_remove_property(args):
    """Remove a property from a Notion database."""
    client = make_client()
    ds_id = args.ds
    name = args.name

    try:
        client.data_sources.update(ds_id, properties={name: None})
        print(f"Property removed: {name}")

    except (APIResponseError, RequestTimeoutError) as e:
        handle_api_error(e)


def cmd_update_row(args):
    """Update an existing row in a Notion database."""
    client = make_client()
    pid = normalize_page_id(args.page_id)

    try:
        # Retrieve the page to find its parent data_source_id
        page = client.pages.retrieve(page_id=pid)
        parent = page.get("parent", {})
        ds_id = parent.get("data_source_id")
        if not ds_id:
            print("Error: page parent has no data_source_id; only pages in SDK-managed databases are supported", file=sys.stderr)
            sys.exit(1)

        schema = _get_schema(client, ds_id)
        row = _read_json_input(args.data_file)
        if not isinstance(row, dict):
            print("Error: update data must be a JSON object", file=sys.stderr)
            sys.exit(1)

        converted = _convert_row(row, schema)
        client.pages.update(page_id=pid, properties=converted)
        print(f"Row updated: {pid}")

    except (APIResponseError, RequestTimeoutError) as e:
        handle_api_error(e)


def main():
    parser = argparse.ArgumentParser(
        description="Edit Notion databases: add rows, modify properties, update rows."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # add-row
    p_add_row = subparsers.add_parser("add-row", help="Add a single row to a database")
    p_add_row.add_argument("--ds", required=True, metavar="DATA_SOURCE_ID",
                           help="Notion data_source_id of the target database")
    p_add_row.add_argument("--data-file", metavar="PATH",
                           help="Path to JSON file with row data (default: stdin)")
    p_add_row.set_defaults(func=cmd_add_row)

    # add-rows
    p_add_rows = subparsers.add_parser("add-rows", help="Add multiple rows to a database")
    p_add_rows.add_argument("--ds", required=True, metavar="DATA_SOURCE_ID",
                            help="Notion data_source_id of the target database")
    p_add_rows.add_argument("--data-file", metavar="PATH",
                            help="Path to JSON file with array of row data (default: stdin)")
    p_add_rows.set_defaults(func=cmd_add_rows)

    # add-property
    p_add_prop = subparsers.add_parser("add-property", help="Add a property to a database")
    p_add_prop.add_argument("--ds", required=True, metavar="DATA_SOURCE_ID",
                            help="Notion data_source_id of the target database")
    p_add_prop.add_argument("--name", required=True, help="Property name")
    p_add_prop.add_argument("--type", required=True, dest="type",
                            help="Property type (e.g. rich_text, number, select, ...)")
    p_add_prop.add_argument("--options", metavar="JSON",
                            help="JSON array of options for select/multi_select")
    p_add_prop.set_defaults(func=cmd_add_property)

    # remove-property
    p_rm_prop = subparsers.add_parser("remove-property", help="Remove a property from a database")
    p_rm_prop.add_argument("--ds", required=True, metavar="DATA_SOURCE_ID",
                           help="Notion data_source_id of the target database")
    p_rm_prop.add_argument("--name", required=True, help="Property name to remove")
    p_rm_prop.set_defaults(func=cmd_remove_property)

    # update-row
    p_upd_row = subparsers.add_parser("update-row", help="Update an existing row")
    p_upd_row.add_argument("--page-id", required=True, metavar="PAGE_ID",
                           help="Page ID or Notion URL of the row to update")
    p_upd_row.add_argument("--data-file", metavar="PATH",
                           help="Path to JSON file with update data (default: stdin)")
    p_upd_row.set_defaults(func=cmd_update_row)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
