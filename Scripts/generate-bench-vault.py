#!/usr/bin/env python3
"""Create synthetic Markdown only in a new destination directory."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", type=Path)
parser.add_argument("count", type=int, choices=(693, 5000))
args = parser.parse_args()
args.destination.mkdir(parents=True, exist_ok=False)
for i in range(args.count):
    (args.destination / f"{i}.md").write_text(
        f"---\nunknown: preserved\n---\n# Note {i}\n"
        + "Project context meeting daily notes the café 计划 [[reference]]\n" * 28,
        encoding="utf-8",
    )
