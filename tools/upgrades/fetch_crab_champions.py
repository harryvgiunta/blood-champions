#!/usr/bin/env python3
"""Pull every upgrade on crabchampions.wiki.gg into one retrievable dataset.

The wiki keeps its five upgrade families on five index pages
(`Weapon Mods`, `Ability Mods`, `Melee Mods`, `Perks`, `Relics`). Each index
page is a run of collapsible blocks, one per upgrade, and each block carries
the data we want as a wikitext list:

    <div class="mw-collapsible mw-collapsed" ...>
    <div style="font-weight:bold;">[[Sharp Shot|<font style="color:#14b1f5;">Sharp Shot</font>]]</div>
    <div class="mw-collapsible-content">
    Shots deal additional flat damage                 <- the one-line effect
    * Shots deal 4 additional flat damage             <- the numbers
    * Spawn weight: 1.0                               <- draw weight
    * Buff scaling: Linear                            <- how stacks add
    * Appears in damage and random chests, ...        <- where it drops
    </div></div>

The name is wrapped in a `font` tag whose colour *is* the rarity
(`#14b1f5` common, `#e619fc` epic, `#d4b20d` legendary, `#ba2902` greed), which
is the only machine-readable rarity on the page - the prose says "rare tier"
for what the colour table calls common, so the colour wins.

Usage:
    python tools/upgrades/fetch_crab_champions.py            # refresh the files
    python tools/upgrades/fetch_crab_champions.py --check    # fetch, diff, exit 1

The two written files sit beside this script and are committed:

    crab_champions_upgrades.json    314 rows, one object per upgrade
    crab_champions_upgrades.csv     the same rows, flat, for grep and spreadsheets

`live: false` marks the nineteen rows the wiki files under "Indefinitely
Removed" and "Removed Weapon Mods" - kept for the record, not part of the pool.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
from pathlib import Path

import requests

API = "https://crabchampions.wiki.gg/api.php"
HERE = Path(__file__).resolve().parent
JSON_PATH = HERE / "crab_champions_upgrades.json"
CSV_PATH = HERE / "crab_champions_upgrades.csv"

# The five index pages, in the wiki's own order, with the family id we use.
INDEX_PAGES = [
    ("Weapon Mods", "weapon"),
    ("Ability Mods", "ability"),
    ("Melee Mods", "melee"),
    ("Perks", "perk"),
    ("Relics", "relic"),
]

# rarity colour -> tier. The wiki's only reliable rarity field.
RARITY_BY_COLOUR = {
    "14b1f5": "common",
    "e619fc": "epic",
    "d4b20d": "legendary",
    "ba2902": "greed",
}

# Sections the wiki keeps but the game no longer fields.
REMOVED_SECTIONS = {"Indefinitely Removed", "Removed Weapon Mods"}

# Metadata bullets that are fields, not effects.
FIELD_BULLETS = (
    "Spawn weight:",
    "Buff scaling:",
    "Debuff scaling:",
    "Tag:",
    "Appears in",
)

WRAP = re.compile(r'<div class="mw-collapsible(?: mw-collapsed)?"[^>]*>')
HEAD = re.compile(r'<div style="font-weight:bold;">(.*?)</div>', re.S)
LINK = re.compile(r"\[\[([^\]|]+)(?:\|(.+?))?\]\]", re.S)
COLOUR = re.compile(r"color:(#[0-9a-fA-F]{6})")

SESSION = requests.Session()
SESSION.headers.update(
    {
        # wiki.gg answers a bare curl UA with a block page; a browser UA does not.
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        ),
        "Accept": "application/json",
    }
)


def api(**params):
    """One API call, retried. A wiki restart mid-crawl is not worth a crash."""
    params = {"format": "json", "formatversion": "2", **params}
    for attempt in range(5):
        try:
            response = SESSION.get(API, params=params, timeout=60)
            response.raise_for_status()
            return response.json()
        except Exception as error:  # noqa: BLE001 - retried, then raised
            if attempt == 4:
                raise
            print(f"  retry {attempt + 1}: {error}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def clean(text: str) -> str:
    """Wikitext and inline HTML down to the words, keeping line structure."""
    text = text.replace("&nbsp;", " ")
    text = re.sub(r"<br\s*/?>", "\n", text)
    text = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("'''", "").replace("''", "")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def fetch_index_pages() -> dict[str, str]:
    """All five index pages in one request: they are small."""
    titles = "|".join(page for page, _ in INDEX_PAGES)
    payload = api(
        action="query", titles=titles, prop="revisions", rvprop="content",
        rvslots="main",
    )
    out = {}
    for page in payload["query"]["pages"]:
        if "revisions" not in page:
            print(f"  missing page: {page['title']}", file=sys.stderr)
            continue
        out[page["title"]] = page["revisions"][0]["slots"]["main"]["content"]
    return out


def parse_index(wikitext: str, family: str) -> list[dict]:
    """One block per upgrade, inside its `== Section ==` heading."""
    rows: list[dict] = []
    parts = re.split(r"\n==\s*([^=\n]+?)\s*==\n", wikitext)
    sections = [("(root)", parts[0])]
    for index in range(1, len(parts) - 1, 2):
        sections.append((parts[index].strip(), parts[index + 1]))

    for section, body in sections:
        starts = [match.start() for match in WRAP.finditer(body)]
        if not starts:
            # A few pages use `=== Name ===` sub-sections instead of blocks.
            sub = re.split(r"\n===\s*([^=\n]+?)\s*===\n", body)
            for index in range(1, len(sub) - 1, 2):
                rows.append(
                    _row(
                        family=family, section=section,
                        name=clean(sub[index]), article=clean(sub[index]),
                        colour=None, content=sub[index + 1],
                    )
                )
            continue
        for index, start in enumerate(starts):
            end = starts[index + 1] if index + 1 < len(starts) else len(body)
            block = body[start:end]
            head = HEAD.search(block)
            if not head:
                continue
            link = LINK.search(head.group(1))
            if not link:
                continue
            content = block.split('<div class="mw-collapsible-content">', 1)
            content = content[1] if len(content) > 1 else ""
            content = re.split(r"</div>\s*</div>", content)[0]
            colour = COLOUR.search(head.group(1))
            rows.append(
                _row(
                    family=family, section=section,
                    name=clean(link.group(2) or link.group(1)),
                    article=link.group(1).strip(),
                    colour=colour.group(1).lower() if colour else None,
                    content=content,
                )
            )
    return rows


def _row(family: str, section: str, name: str, article: str,
         colour: str | None, content: str) -> dict:
    """One upgrade block -> one dataset row."""
    lines = [clean(line) for line in content.split("\n")]
    lines = [line for line in lines if line]
    bullets = [line[1:].strip() for line in lines if line.startswith("*")]
    prose = [line for line in lines if not line.startswith("*")]

    effects, notes, sources = [], [], ""
    for bullet in bullets:
        if bullet.startswith("Spawn weight:"):
            continue
        if bullet.startswith("Buff scaling:"):
            continue
        if bullet.startswith("Debuff scaling:"):
            continue
        if bullet.startswith("Tag:"):
            continue
        if bullet.startswith("Appears in"):
            sources = bullet
            continue
        effects.append(bullet)

    weight = re.search(r"Spawn weight:\s*([0-9.]+)", content)
    buff = re.search(r"Buff scaling:\s*(\w+)", content)
    debuff = re.search(r"Debuff scaling:\s*(\w+)", content)
    tag = re.search(r"Tag:\s*([^\n]+)", content)

    rarity = RARITY_BY_COLOUR.get(colour[1:] if colour else "", None) if colour else None
    return {
        "id": f"{family}:{slug(article)}",
        "name": name,
        "article": article,
        "family": family,
        "section": section,
        "rarity": rarity,
        "rarity_colour": colour,
        "spawn_weight": float(weight.group(1)) if weight else None,
        "buff_scaling": buff.group(1).lower() if buff else None,
        "debuff_scaling": debuff.group(1).lower() if debuff else None,
        "tag": clean(tag.group(1)) if tag else None,
        "tagline": prose[0] if prose else "",
        "effects": effects,
        "notes": notes,
        "sources": sources,
        "text": clean(content),
        "live": section not in REMOVED_SECTIONS,
        "source_url": "https://crabchampions.wiki.gg/wiki/"
        + article.replace(" ", "_"),
    }


def page_notes(titles: list[str]) -> dict[str, dict]:
    """The per-upgrade article, where one exists, for its Scaling note."""
    out: dict[str, dict] = {}
    titles = sorted(titles)
    for start in range(0, len(titles), 20):
        batch = titles[start : start + 20]
        payload = api(
            action="query", titles="|".join(batch), prop="revisions",
            rvprop="content", rvslots="main",
        )
        for page in payload["query"]["pages"]:
            if "revisions" not in page:
                continue
            text = page["revisions"][0]["slots"]["main"]["content"]
            scaling = re.search(r"==\s*Scaling\s*==\s*\n(.*?)(?:\n==|\Z)", text, re.S)
            lead = clean(text.split("\n", 1)[0])
            out[page["title"]] = {
                "lead": lead,
                "scaling": clean(scaling.group(1)) if scaling else "",
                "has_article": True,
            }
    return out


def build() -> dict:
    pages = fetch_index_pages()
    rows: list[dict] = []
    for title, family in INDEX_PAGES:
        if title not in pages:
            continue
        parsed = parse_index(pages[title], family)
        print(f"  {title}: {len(parsed)} rows", file=sys.stderr)
        rows.extend(parsed)

    notes = page_notes([row["article"] for row in rows])
    for row in rows:
        note = notes.get(row["article"], {})
        row["has_article"] = note.get("has_article", False)
        row["article_lead"] = note.get("lead", "")
        row["article_scaling"] = note.get("scaling", "")

    rows.sort(key=lambda row: (row["family"], not row["live"], row["section"],
                               row["name"].lower()))
    return {
        "source": {
            "wiki": "https://crabchampions.wiki.gg",
            "api": API,
            "fetched": time.strftime("%Y-%m-%d"),
            "game_version": "v2372 (as the wiki files the index pages)",
            "rarity_colours": {value: key for key, value in RARITY_BY_COLOUR.items()},
            "families": [family for _, family in INDEX_PAGES],
            "note": "Rarity comes from the name's colour on the index page; the "
            "prose calls the common tier 'rare' in places.",
        },
        "counts": {
            "rows": len(rows),
            "live": sum(1 for row in rows if row["live"]),
        },
        "upgrades": rows,
    }


def write_csv(rows: list[dict]) -> None:
    fields = [
        "id", "name", "article", "family", "section", "rarity",
        "spawn_weight", "buff_scaling", "debuff_scaling", "tag", "tagline",
        "effects", "sources", "live", "has_article", "source_url",
    ]
    with CSV_PATH.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            flat = dict(row)
            flat["effects"] = " | ".join(row["effects"])
            writer.writerow(flat)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fetch and compare against the committed files")
    args = parser.parse_args()

    print("fetching crabchampions.wiki.gg ...", file=sys.stderr)
    data = build()
    rows = data["upgrades"]
    live = sum(1 for row in rows if row["live"])
    print(f"  {len(rows)} rows, {live} live", file=sys.stderr)

    if args.check:
        if not JSON_PATH.exists():
            print("no committed dataset to check against", file=sys.stderr)
            return 1
        old = json.loads(JSON_PATH.read_text(encoding="utf-8"))
        if old.get("upgrades") == rows:
            print("dataset is current", file=sys.stderr)
            return 0
        old_by_id = {row["id"]: row for row in old.get("upgrades", [])}
        new_by_id = {row["id"]: row for row in rows}
        for key in sorted(set(old_by_id) | set(new_by_id)):
            if old_by_id.get(key) != new_by_id.get(key):
                print(f"  changed: {key}", file=sys.stderr)
        return 1

    JSON_PATH.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n",
                         encoding="utf-8")
    write_csv(rows)
    print(f"wrote {JSON_PATH.name} and {CSV_PATH.name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
