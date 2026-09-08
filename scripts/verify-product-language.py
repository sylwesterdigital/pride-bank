#!/usr/bin/env python3
"""Guard user-facing prototype copy against unwanted product language."""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1] / "web"

FORBIDDEN = {
    "wallet": re.compile(r"\bwallets?\b", re.I),
    "token": re.compile(r"\btokens?\b", re.I),
    "coin": re.compile(r"\bcoins?\b", re.I),
    "crypto": re.compile(r"\bcrypto(?:currency|currencies)?\b", re.I),
    "blockchain": re.compile(r"\bblockchain\b", re.I),
    "trading": re.compile(r"\btrading\b", re.I),
    "exchange": re.compile(r"\bexchange\b", re.I),
    "staking": re.compile(r"\bstaking\b", re.I),
    "gas": re.compile(r"\bgas\b", re.I),
    "mint": re.compile(r"\bmint(?:ed|ing)?\b", re.I),
    "web3": re.compile(r"\bweb3\b", re.I),
    "withdraw": re.compile(r"\bwithdraw(?:al|als|ing)?\b", re.I),
    "on-chain": re.compile(r"\bon[- ]chain\b", re.I),
    "nft": re.compile(r"\bnfts?\b", re.I),
    "metaverse": re.compile(r"\bmetaverse\b", re.I),
    "floor price": re.compile(r"\bfloor\s+price\b", re.I),
    "virtual real estate": re.compile(r"\bvirtual\s+real\s+estate\b", re.I),
}

issues: list[str] = []
for path in sorted(ROOT.rglob("*")):
    if not path.is_file() or path.suffix.lower() not in {".html", ".js", ".css"}:
        continue
    text = path.read_text(encoding="utf-8")
    for label, pattern in FORBIDDEN.items():
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            issues.append(f"{path.relative_to(ROOT)}:{line}: forbidden product term '{label}'")

if issues:
    print("\n".join(issues), file=sys.stderr)
    raise SystemExit(1)

print("Product language OK")
