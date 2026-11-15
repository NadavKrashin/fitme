#!/usr/bin/env python3
"""Checks docs/store/APP_STORE_LISTING.md against App Store Connect's length limits."""
import re
import sys
from pathlib import Path

text = Path(__file__).resolve().parent.parent.joinpath("docs/store/APP_STORE_LISTING.md").read_text()


def inline(label: str) -> str:
    match = re.search(rf"\*\*{re.escape(label)}\*\* \[\d+\]: (.+)", text)
    if not match:
        sys.exit(f"missing {label}")
    return match.group(1).strip()


def block(label: str, end: str) -> str:
    start = text.index(f"**{label}**")
    body = text[text.index("\n", start) : text.index(end, start)].strip()
    # Markdown wraps lines; App Store Connect gets paragraphs.
    paragraphs = [" ".join(p.split()) for p in body.split("\n\n")]
    return "\n\n".join(paragraphs)


fields = {
    "Name": (inline("Name"), 30),
    "Subtitle": (inline("Subtitle"), 30),
    "Promotional text": (block("Promotional text", "**Description**"), 170),
    "Description": (block("Description", "**Keywords**"), 4000),
    "Keywords": (inline("Keywords"), 100),
    "App Review notes": (text.split("## App Review notes [4000]", 1)[1].strip(), 4000),
}
failed = False
for name, (value, limit) in fields.items():
    status = "ok" if len(value) <= limit else "TOO LONG"
    failed |= len(value) > limit
    print(f"{name:18} {len(value):5} / {limit:<5} {status}")
keywords = inline("Keywords")
if " " in keywords:
    print("Keywords: no spaces after commas (they count against the limit)")
    failed = True
sys.exit(1 if failed else 0)
