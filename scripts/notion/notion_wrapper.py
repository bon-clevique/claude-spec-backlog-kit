"""Shared utilities for Notion SDK scripts.

Provides client initialization, ID normalization, block pagination,
and conversion helpers used by read_page.py, create_db.py, edit_db.py.
"""

from __future__ import annotations

import os
import re
import sys
import httpx
from notion_client import Client
from notion_client.errors import APIResponseError, RequestTimeoutError


NOTION_API_VERSION = "2026-03-11"


CLIENT_TIMEOUT = 60  # seconds


def make_client() -> Client:
    """Create a Notion SDK client using NOTION_API_KEY from environment."""
    api_key = os.environ.get("NOTION_API_KEY")
    if not api_key:
        print("Error: NOTION_API_KEY is not set", file=sys.stderr)
        print("  Please set it in .zshenv", file=sys.stderr)
        sys.exit(1)
    return Client(
        auth=api_key,
        notion_version=NOTION_API_VERSION,
        client=httpx.Client(timeout=httpx.Timeout(CLIENT_TIMEOUT)),
    )


def normalize_page_id(url_or_id: str) -> str:
    """Extract a page/block ID from a Notion URL or pass through a raw ID.

    Supports formats:
      - https://www.notion.so/Page-Title-<32hex>
      - https://www.notion.so/workspace/Page-Title-<32hex>
      - https://www.notion.so/<32hex>
      - https://www.notion.so/<uuid>
      - <32hex> or <uuid> directly
    """
    url_or_id = url_or_id.strip()

    # UUID with dashes
    uuid_pattern = re.compile(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        re.IGNORECASE,
    )
    match = uuid_pattern.search(url_or_id)
    if match:
        return match.group(0)

    # 32-char hex (no dashes) — extract from URL or raw
    hex32_pattern = re.compile(r"[0-9a-f]{32}", re.IGNORECASE)
    match = hex32_pattern.search(url_or_id)
    if match:
        h = match.group(0)
        return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"

    # Fallback: return as-is and let the API error
    return url_or_id


_MAX_BLOCK_DEPTH = 10


def paginate_blocks(client: Client, block_id: str, recursive: bool = True, _depth: int = 0) -> list:  # noqa: C901
    """Fetch all child blocks, optionally recursing into nested blocks."""
    blocks: list = []
    cursor = None
    while True:
        kwargs = {"block_id": block_id, "page_size": 100}
        if cursor:
            kwargs["start_cursor"] = cursor
        resp = client.blocks.children.list(**kwargs)
        results = resp["results"]  # type: ignore[index]
        for block in results:
            blocks.append(block)
            if recursive and block.get("has_children") and _depth < _MAX_BLOCK_DEPTH:  # type: ignore[union-attr]
                children = paginate_blocks(client, block["id"], recursive=True, _depth=_depth + 1)  # type: ignore[index]
                block["_children"] = children  # type: ignore[index]
        if not resp.get("has_more"):  # type: ignore[union-attr]
            break
        cursor = resp.get("next_cursor")  # type: ignore[union-attr]
    return blocks


def _rich_text_to_str(rich_texts: list) -> str:
    """Convert Notion rich_text array to plain string."""
    return "".join(rt.get("plain_text", "") for rt in rich_texts)


def _block_to_markdown(block: dict, indent: int = 0) -> str:
    """Convert a single Notion block to Markdown text."""
    btype = block.get("type", "")
    data = block.get(btype, {})
    prefix = "  " * indent
    text = _rich_text_to_str(data.get("rich_text", []))

    lines = []

    if btype == "paragraph":
        lines.append(f"{prefix}{text}")
    elif btype == "heading_1":
        lines.append(f"{prefix}# {text}")
    elif btype == "heading_2":
        lines.append(f"{prefix}## {text}")
    elif btype == "heading_3":
        lines.append(f"{prefix}### {text}")
    elif btype == "bulleted_list_item":
        lines.append(f"{prefix}- {text}")
    elif btype == "numbered_list_item":
        lines.append(f"{prefix}1. {text}")
    elif btype == "to_do":
        checked = "x" if data.get("checked") else " "
        lines.append(f"{prefix}- [{checked}] {text}")
    elif btype == "toggle":
        lines.append(f"{prefix}<details><summary>{text}</summary>")
    elif btype == "quote":
        lines.append(f"{prefix}> {text}")
    elif btype == "callout":
        icon = data.get("icon", {}).get("emoji", "")
        lines.append(f"{prefix}> {icon} {text}")
    elif btype == "code":
        lang = data.get("language", "")
        lines.append(f"{prefix}```{lang}")
        lines.append(f"{prefix}{text}")
        lines.append(f"{prefix}```")
    elif btype == "divider":
        lines.append(f"{prefix}---")
    elif btype == "table":
        # Table blocks have children (table_row) in _children
        pass
    elif btype == "table_row":
        cells = data.get("cells", [])
        cell_texts = [_rich_text_to_str(cell) for cell in cells]
        lines.append(f"{prefix}| {' | '.join(cell_texts)} |")
    elif btype == "child_database":
        title = data.get("title", "")
        lines.append(f"{prefix}[Database: {title}]")
    elif btype == "child_page":
        title = data.get("title", "")
        lines.append(f"{prefix}[Page: {title}]")
    elif btype == "image":
        url = ""
        if data.get("type") == "external":
            url = data.get("external", {}).get("url", "")
        elif data.get("type") == "file":
            url = data.get("file", {}).get("url", "")
        caption = _rich_text_to_str(data.get("caption", []))
        lines.append(f"{prefix}![{caption}]({url})")
    elif btype == "bookmark":
        url = data.get("url", "")
        caption = _rich_text_to_str(data.get("caption", []))
        lines.append(f"{prefix}[{caption or url}]({url})")
    elif btype == "equation":
        expr = data.get("expression", "")
        lines.append(f"{prefix}$${expr}$$")
    else:
        if text:
            lines.append(f"{prefix}{text}")

    # Process nested children
    children = block.get("_children", [])
    if children:
        is_table = btype == "table"
        for i, child in enumerate(children):
            child_md = _block_to_markdown(child, indent if is_table else indent + 1)
            lines.append(child_md)
            # Add separator row after first table_row (header)
            if is_table and i == 0 and child.get("type") == "table_row":
                cells = child.get("table_row", {}).get("cells", [])
                sep = f"{prefix}| {' | '.join(['---'] * len(cells))} |"
                lines.append(sep)

    if btype == "toggle" and children:
        lines.append(f"{prefix}</details>")

    return "\n".join(lines)


def blocks_to_markdown(blocks: list) -> str:
    """Convert a list of Notion blocks to Markdown."""
    parts = []
    for block in blocks:
        md = _block_to_markdown(block)
        if md:
            parts.append(md)
    return "\n\n".join(parts)


def props_to_dict(properties: dict) -> dict:
    """Convert Notion page properties to a human-readable dict."""
    result = {}
    for name, prop in properties.items():
        ptype = prop.get("type", "")
        if ptype == "title":
            result[name] = _rich_text_to_str(prop.get("title", []))
        elif ptype == "rich_text":
            result[name] = _rich_text_to_str(prop.get("rich_text", []))
        elif ptype == "number":
            result[name] = prop.get("number")
        elif ptype == "select":
            sel = prop.get("select")
            result[name] = sel.get("name", "") if sel else None
        elif ptype == "multi_select":
            result[name] = [s.get("name", "") for s in prop.get("multi_select", [])]
        elif ptype == "status":
            st = prop.get("status")
            result[name] = st.get("name", "") if st else None
        elif ptype == "date":
            d = prop.get("date")
            if d:
                result[name] = d.get("start", "")
                if d.get("end"):
                    result[name] += f" → {d['end']}"
            else:
                result[name] = None
        elif ptype == "checkbox":
            result[name] = prop.get("checkbox", False)
        elif ptype == "url":
            result[name] = prop.get("url")
        elif ptype == "email":
            result[name] = prop.get("email")
        elif ptype == "phone_number":
            result[name] = prop.get("phone_number")
        elif ptype == "formula":
            formula = prop.get("formula", {})
            ftype = formula.get("type", "")
            result[name] = formula.get(ftype)
        elif ptype == "relation":
            result[name] = [r.get("id", "") for r in prop.get("relation", [])]
        elif ptype == "rollup":
            rollup = prop.get("rollup", {})
            rtype = rollup.get("type", "")
            result[name] = rollup.get(rtype)
        elif ptype == "people":
            result[name] = [
                p.get("name", p.get("id", "")) for p in prop.get("people", [])
            ]
        elif ptype == "files":
            result[name] = [
                f.get("name", f.get(f.get("type", ""), {}).get("url", ""))
                for f in prop.get("files", [])
            ]
        elif ptype == "created_time":
            result[name] = prop.get("created_time")
        elif ptype == "last_edited_time":
            result[name] = prop.get("last_edited_time")
        elif ptype == "created_by":
            result[name] = prop.get("created_by", {}).get("name", "")
        elif ptype == "last_edited_by":
            result[name] = prop.get("last_edited_by", {}).get("name", "")
        elif ptype == "unique_id":
            uid = prop.get("unique_id", {})
            prefix = uid.get("prefix", "")
            number = uid.get("number", "")
            result[name] = f"{prefix}-{number}" if prefix else str(number)
        else:
            result[name] = f"[{ptype}]"
    return result


def handle_api_error(e: APIResponseError | RequestTimeoutError):
    """Print a formatted API error to stderr and exit."""
    if isinstance(e, RequestTimeoutError):
        print("Notion API error: request timed out", file=sys.stderr)
        print(f"  Current timeout: {CLIENT_TIMEOUT}s. Retry or check Notion status.", file=sys.stderr)
        sys.exit(1)
    print(f"Notion API error: {e.code} - {e}", file=sys.stderr)
    if e.code == "unauthorized":
        print("  Check NOTION_API_KEY in .zshenv", file=sys.stderr)
    elif e.code == "object_not_found":
        print("  Check the page/database ID and integration permissions", file=sys.stderr)
    elif e.code == "restricted_resource":
        print("  The integration does not have access to this resource", file=sys.stderr)
    elif e.code == "rate_limited":
        print("  Rate limited — wait and retry", file=sys.stderr)
    sys.exit(1)
