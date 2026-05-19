#!/usr/bin/env python3
"""Read a Notion page and output its content."""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from notion_client.errors import APIResponseError, RequestTimeoutError
from notion_wrapper import (
    blocks_to_markdown,
    handle_api_error,
    make_client,
    normalize_page_id,
    paginate_blocks,
    props_to_dict,
)


def get_title(props: dict) -> str:
    for v in props.values():
        if v.get("type") == "title":
            parts = v.get("title", [])
            return "".join(p.get("plain_text", "") for p in parts)
    return "Untitled"


def output_json(page: dict, blocks: list) -> None:
    data = {
        "properties": props_to_dict(page["properties"]),
        "blocks": blocks,
    }
    print(json.dumps(data, ensure_ascii=False, indent=2))


def output_markdown(page: dict, blocks: list) -> None:
    props = props_to_dict(page["properties"])
    title = get_title(page["properties"])
    lines = [f"# {title}", "", "## Properties"]
    for k, v in props.items():
        lines.append(f"{k}: {v}")
    lines += ["", "## Content", blocks_to_markdown(blocks)]
    print("\n".join(lines))


def output_text(page: dict, blocks: list) -> None:
    props = props_to_dict(page["properties"])
    title = get_title(page["properties"])
    lines = [f"[{title}]", "", "Properties:"]
    for k, v in props.items():
        lines.append(f"  {k}: {v}")
    lines += ["", "Content:", blocks_to_markdown(blocks)]
    print("\n".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser(description="Read a Notion page")
    parser.add_argument("url_or_id", help="Notion page URL or page ID")
    parser.add_argument(
        "--format",
        choices=["json", "markdown", "text"],
        default="text",
        help="Output format (default: text)",
    )
    args = parser.parse_args()

    try:
        client = make_client()
        pid = normalize_page_id(args.url_or_id)
        page = client.pages.retrieve(page_id=pid)
        blocks = paginate_blocks(client, pid)

        if args.format == "json":
            output_json(page, blocks)
        elif args.format == "markdown":
            output_markdown(page, blocks)
        else:
            output_text(page, blocks)

    except (APIResponseError, RequestTimeoutError) as e:
        handle_api_error(e)


if __name__ == "__main__":
    main()
