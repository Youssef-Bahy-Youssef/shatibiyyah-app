"""Writes test/fixtures/search_parity.json: what `spd search` finds for 20 sample
queries (plan P6 acceptance), for test/search_test.dart to hold the app against.

The pipeline searches FTS5 tokens, the app substrings, so for one-word queries
every pipeline hit is an app hit. Commentary hits are counted as the app shows
them: one per block, blocks with a verse, citation lead-ins left out.

    ../../shatibiyyah-data/.venv/bin/python tool/search_parity.py
"""

import json
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[3] / "shatibiyyah-data"
sys.path.insert(0, str(DATA / "src"))

from shatibiyyah.config import load_config  # noqa: E402
from shatibiyyah.db import Database  # noqa: E402
from shatibiyyah.paths import database_path  # noqa: E402
from shatibiyyah.query import Repository  # noqa: E402

QUERIES = [
    "ورش", "حمزة", "النقل", "بدأت", "الإدغام", "الإمالة", "السكت", "قالون", "هشام", "البسملة",
    "الهمز", "المد", "الراء", "اللام", "التسهيل", "الكسائي", "عاصم", "الوقف", "الياءات", "شعبة",
]

config = load_config(DATA / "config" / "default.yaml")
with Database(database_path(config, None), read_only=True) as db:
    repo = Repository(db, config)
    cases = []
    for q in QUERIES:
        verses = sorted({h["verseNumber"] for h in repo.search_matn(q, limit=100000)})
        blocks = {
            h["blockId"]
            for h in repo.search_commentary(q, limit=100000)
            if h["fromVerse"] is not None and h["segmentType"] != "citation_lead_in"
        }
        cases.append({"query": q, "verses": verses, "commentary_blocks": len(blocks)})
out = Path(__file__).resolve().parents[1] / "test" / "fixtures" / "search_parity.json"
out.write_text(json.dumps({"source": "spd search (FTS5), shatibiyyah-data", "cases": cases},
                          ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{len(cases)} queries -> {out}")
