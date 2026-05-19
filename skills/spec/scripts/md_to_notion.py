#!/usr/bin/env python3
"""md_to_notion.py — Convert a Markdown file to Notion blocks and create/update a page.

Usage:
    # Create a new page in the spec DB
    python md_to_notion.py create --md <path> --title <title> [--repo <repo-name>]

    # Update an existing page (replaces all children blocks)
    python md_to_notion.py update --md <path> --page-id <page-id>

Environment:
    NOTION_API_KEY        — required
    NOTION_SPEC_DATA_SOURCE_ID — data_source_id of the spec DB
                                (default: <UUID>)

Output:
    On success, prints JSON: {"page_id": "...", "url": "..."}
    On failure, prints error to stderr and exits 1.

Supported md elements (subset sufficient for /spec template):
    - heading_1/2/3 (#, ##, ###)
    - paragraph with bold (**x**), italic (*x*), inline code (`x`)
    - bulleted_list_item (- )
    - numbered_list_item (1. 2. ...)
    - code block (``` lang ... ```) — language captured, mermaid supported
    - quote (> )
    - divider (---)
    - tables (| header | ... | separator | rows |)

Unsupported (silently ignored or rendered as paragraph):
    - images, footnotes, nested lists beyond 2 levels
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Iterable

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "scripts", "notion"))

from notion_wrapper import make_client, handle_api_error  # type: ignore
from notion_client.errors import APIResponseError, RequestTimeoutError  # type: ignore


DEFAULT_DATA_SOURCE_ID = "<UUID>"
NOTION_BLOCK_LIMIT = 100  # max children blocks per single API call
NOTION_RICH_TEXT_LIMIT = 2000  # max length of a single rich_text content


# ---------- Inline parsing ----------

_INLINE_RE = re.compile(
    r"(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)"
)


def parse_inline(text: str) -> list[dict]:
    """Split a paragraph text into Notion rich_text array with annotations.

    Recognizes: **bold**, *italic*, `code`. Plain text otherwise.
    """
    parts: list[dict] = []
    pos = 0
    for m in _INLINE_RE.finditer(text):
        start, end = m.span()
        if start > pos:
            parts.append(_text_run(text[pos:start]))
        token = m.group(0)
        if token.startswith("**") and token.endswith("**"):
            parts.append(_text_run(token[2:-2], bold=True))
        elif token.startswith("`") and token.endswith("`"):
            parts.append(_text_run(token[1:-1], code=True))
        elif token.startswith("*") and token.endswith("*"):
            parts.append(_text_run(token[1:-1], italic=True))
        else:
            parts.append(_text_run(token))
        pos = end
    if pos < len(text):
        parts.append(_text_run(text[pos:]))
    return [p for p in parts if p["text"]["content"]]


def _text_run(content: str, **annotations) -> dict:
    """Build a single rich_text segment, truncating to Notion's limit."""
    if len(content) > NOTION_RICH_TEXT_LIMIT:
        content = content[: NOTION_RICH_TEXT_LIMIT - 3] + "..."
    return {
        "type": "text",
        "text": {"content": content},
        "annotations": {
            "bold": annotations.get("bold", False),
            "italic": annotations.get("italic", False),
            "strikethrough": False,
            "underline": False,
            "code": annotations.get("code", False),
            "color": "default",
        },
    }


# ---------- Block builders ----------


def _heading_block(level: int, text: str) -> dict:
    btype = f"heading_{level}"
    return {
        "object": "block",
        "type": btype,
        btype: {"rich_text": parse_inline(text)},
    }


def _paragraph_block(text: str) -> dict:
    return {
        "object": "block",
        "type": "paragraph",
        "paragraph": {"rich_text": parse_inline(text)},
    }


def _bulleted_block(text: str) -> dict:
    return {
        "object": "block",
        "type": "bulleted_list_item",
        "bulleted_list_item": {"rich_text": parse_inline(text)},
    }


def _numbered_block(text: str) -> dict:
    return {
        "object": "block",
        "type": "numbered_list_item",
        "numbered_list_item": {"rich_text": parse_inline(text)},
    }


def _quote_block(text: str) -> dict:
    return {
        "object": "block",
        "type": "quote",
        "quote": {"rich_text": parse_inline(text)},
    }


_NOTION_LANGUAGES = {
    "mermaid", "python", "javascript", "typescript", "bash", "shell", "json",
    "yaml", "markdown", "html", "css", "swift", "kotlin", "java", "ruby",
    "rust", "go", "sql", "diff", "gherkin", "plain text",
}


def _code_block(lang: str, content: str) -> dict:
    lang_norm = (lang or "").strip().lower()
    if lang_norm == "":
        lang_norm = "plain text"
    elif lang_norm not in _NOTION_LANGUAGES:
        lang_norm = "plain text"
    return {
        "object": "block",
        "type": "code",
        "code": {
            "rich_text": [_text_run(content)],
            "language": lang_norm,
        },
    }


def _divider_block() -> dict:
    return {"object": "block", "type": "divider", "divider": {}}


# ---------- Table support ----------


def _is_table_separator(line: str) -> bool:
    """`|---|---|` のような行を判定。malformed `||` (cell=1) は false。"""
    if not (line.startswith("|") and line.endswith("|")):
        return False
    inner = line[1:-1]
    cells = inner.split("|")
    if len(cells) < 2:  # reject `||` malformed
        return False
    return all(c.strip().replace("-", "").replace(":", "") == "" for c in cells)


def _parse_table_row(line: str) -> list[str]:
    """`| a | b | c |` -> ["a", "b", "c"]。各 cell は Notion rich_text 上限 (2000) で truncate。"""
    inner = line.strip()[1:-1]
    cells = [c.strip() for c in inner.split("|")]
    # Truncate to Notion rich_text per-block limit (2000 chars)
    return [c if len(c) <= 1997 else c[:1997] + "..." for c in cells]


def _table_row_block(cells: list[str]) -> dict:
    return {
        "object": "block",
        "type": "table_row",
        "table_row": {
            "cells": [[{"type": "text", "text": {"content": c}}] for c in cells],
        },
    }


def _table_block(header: list[str], rows: list[list[str]]) -> dict:
    table_width = len(header)
    children = [_table_row_block(header)]
    for r in rows:
        if len(r) > table_width:
            sys.stderr.write(
                f"[md_to_notion] WARN: table row has {len(r)} cells > header {table_width}, truncating: {r[:2]}...\n"
            )
        padded = r + [""] * max(0, table_width - len(r))
        children.append(_table_row_block(padded[:table_width]))
    return {
        "object": "block",
        "type": "table",
        "table": {
            "table_width": table_width,
            "has_column_header": True,
            "has_row_header": False,
            "children": children,
        },
    }


def _handle_table_at(lines: list[str], i: int) -> "tuple[dict | None, int]":
    """Return (table_block, new_index) if a table starts at lines[i], else (None, i)."""
    line = lines[i]
    if not (line.startswith("|") and line.endswith("|") and len(line) >= 2):
        return None, i
    if i + 1 >= len(lines) or not _is_table_separator(lines[i + 1]):
        return None, i
    header = _parse_table_row(line)
    j = i + 2
    rows: list[list[str]] = []
    while j < len(lines) and lines[j].startswith("|") and lines[j].endswith("|") and len(lines[j]) >= 2:
        rows.append(_parse_table_row(lines[j]))
        j += 1
    return _table_block(header, rows), j


# ---------- Markdown parser ----------


def md_to_blocks(md: str) -> list[dict]:
    """Convert Markdown text to a list of Notion block dicts.

    Strategy: scan line-by-line. Detect code fences first, then headings, list,
    quote, divider, blank lines, otherwise paragraph (with consecutive non-blank
    lines joined into one paragraph).
    """
    blocks: list[dict] = []
    lines = md.splitlines()
    i = 0
    paragraph_buf: list[str] = []
    quote_buf: list[str] = []

    def flush_paragraph():
        nonlocal paragraph_buf
        if paragraph_buf:
            text = " ".join(paragraph_buf).strip()
            if text:
                blocks.append(_paragraph_block(text))
            paragraph_buf = []

    def flush_quote():
        nonlocal quote_buf
        if quote_buf:
            text = " ".join(quote_buf).strip()
            if text:
                blocks.append(_quote_block(text))
            quote_buf = []

    while i < len(lines):
        line = lines[i]

        # Table — header row + separator row + body rows
        # Must be checked before paragraph/list branches so table rows are not consumed elsewhere.
        table_block, new_i = _handle_table_at(lines, i)
        if table_block is not None:
            flush_paragraph()
            flush_quote()
            blocks.append(table_block)
            i = new_i
            continue

        # Code fence
        if line.startswith("```"):
            flush_paragraph()
            flush_quote()
            lang = line[3:].strip()
            i += 1
            code_lines: list[str] = []
            while i < len(lines) and not lines[i].startswith("```"):
                code_lines.append(lines[i])
                i += 1
            blocks.append(_code_block(lang, "\n".join(code_lines)))
            i += 1  # skip closing fence
            continue

        # Heading
        if line.startswith("### "):
            flush_paragraph()
            flush_quote()
            blocks.append(_heading_block(3, line[4:].strip()))
            i += 1
            continue
        if line.startswith("## "):
            flush_paragraph()
            flush_quote()
            blocks.append(_heading_block(2, line[3:].strip()))
            i += 1
            continue
        if line.startswith("# "):
            flush_paragraph()
            flush_quote()
            blocks.append(_heading_block(1, line[2:].strip()))
            i += 1
            continue

        # Divider
        if line.strip() == "---":
            flush_paragraph()
            flush_quote()
            blocks.append(_divider_block())
            i += 1
            continue

        # Quote
        if line.startswith("> "):
            flush_paragraph()
            quote_buf.append(line[2:])
            i += 1
            continue
        if line.startswith(">"):
            flush_paragraph()
            quote_buf.append(line[1:].lstrip())
            i += 1
            continue

        # Bulleted list
        m = re.match(r"^(\s*)[-*] (.+)$", line)
        if m:
            flush_paragraph()
            flush_quote()
            blocks.append(_bulleted_block(m.group(2).strip()))
            i += 1
            continue

        # Numbered list
        m = re.match(r"^(\s*)\d+\. (.+)$", line)
        if m:
            flush_paragraph()
            flush_quote()
            blocks.append(_numbered_block(m.group(2).strip()))
            i += 1
            continue

        # Blank line — flush paragraph/quote
        if line.strip() == "":
            flush_paragraph()
            flush_quote()
            i += 1
            continue

        # Default: accumulate paragraph
        flush_quote()
        paragraph_buf.append(line.strip())
        i += 1

    flush_paragraph()
    flush_quote()
    return blocks


# ---------- Notion API operations ----------


def _chunks(seq: list, n: int) -> Iterable[list]:
    for i in range(0, len(seq), n):
        yield seq[i : i + n]


def create_page(client, data_source_id: str, title: str, repo: str | None, blocks: list[dict]) -> dict:
    """Create a new page in the spec DB.

    Properties set:
      - 設計名 (title) <- title
      - Repo/Project (rich_text) <- repo (if given)
      - ステータス (status) <- "Plan"
    """
    properties: dict = {
        "設計名": {"title": [{"type": "text", "text": {"content": title}}]},
        "ステータス": {"status": {"name": "Plan"}},
    }
    if repo:
        properties["Repo/Project"] = {
            "rich_text": [{"type": "text", "text": {"content": repo}}]
        }

    # First page-create call carries the first 100 blocks (Notion API limit).
    head, *tail = list(_chunks(blocks, NOTION_BLOCK_LIMIT)) or [[]]
    page = client.pages.create(
        parent={"type": "data_source_id", "data_source_id": data_source_id},
        properties=properties,
        children=head,
    )
    page_id = page["id"]

    # Append remaining blocks in 100-chunks
    for batch in tail:
        client.blocks.children.append(block_id=page_id, children=batch)

    uid_prop = page.get("properties", {}).get("ID", {})
    uid = uid_prop.get("unique_id", {})
    prefix = uid.get("prefix", "")
    number = uid.get("number")
    unique_id_str = f"{prefix}-{number}" if (prefix and number is not None) else ""
    return {"page_id": page_id, "url": page.get("url", ""), "unique_id": unique_id_str}


def update_page(client, page_id: str, blocks: list[dict]) -> dict:
    """Replace all children of the page with new blocks.

    Strategy: delete all existing children (archive=True), then append new.
    """
    # List existing children
    existing = []
    cursor = None
    while True:
        resp = client.blocks.children.list(
            block_id=page_id,
            page_size=100,
            **({"start_cursor": cursor} if cursor else {}),
        )
        existing.extend(resp.get("results", []))
        if not resp.get("has_more"):
            break
        cursor = resp.get("next_cursor")

    # Archive each existing child block
    for b in existing:
        client.blocks.delete(block_id=b["id"])

    # Append new blocks in 100-chunks
    for batch in _chunks(blocks, NOTION_BLOCK_LIMIT):
        client.blocks.children.append(block_id=page_id, children=batch)

    # Fetch page meta to get URL
    page = client.pages.retrieve(page_id=page_id)
    return {"page_id": page_id, "url": page.get("url", "")}


# ---------- CLI ----------


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    p_create = sub.add_parser("create", help="Create a new page in the spec DB")
    p_create.add_argument("--md", required=True, help="Path to markdown file")
    p_create.add_argument("--title", required=True, help="Page title (= 設計名)")
    p_create.add_argument("--repo", help="Repo/Project name (cwd basename or explicit)")
    p_create.add_argument(
        "--data-source-id",
        default=os.environ.get("NOTION_SPEC_DATA_SOURCE_ID", DEFAULT_DATA_SOURCE_ID),
        help="data_source_id of the spec DB (default: env or built-in)",
    )

    p_update = sub.add_parser("update", help="Replace children of an existing page")
    p_update.add_argument("--md", required=True, help="Path to markdown file")
    p_update.add_argument("--page-id", required=True, help="Notion page ID to overwrite")

    return p.parse_args()


def main() -> None:
    args = parse_args()

    try:
        with open(args.md, "r", encoding="utf-8") as f:
            md_text = f.read()
    except OSError as exc:
        print(f"Error: cannot read md file: {exc}", file=sys.stderr)
        sys.exit(1)

    blocks = md_to_blocks(md_text)
    if not blocks:
        print("Error: md file produced no blocks (empty or unsupported)", file=sys.stderr)
        sys.exit(1)

    client = make_client()

    try:
        if args.cmd == "create":
            result = create_page(client, args.data_source_id, args.title, args.repo, blocks)
        elif args.cmd == "update":
            result = update_page(client, args.page_id, blocks)
        else:
            print(f"Error: unknown command: {args.cmd}", file=sys.stderr)
            sys.exit(1)
    except (APIResponseError, RequestTimeoutError) as exc:
        handle_api_error(exc)
        return  # unreachable; handle_api_error calls sys.exit

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
