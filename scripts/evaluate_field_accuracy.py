#!/usr/bin/env python3
"""Compatibility entry point for the parser evaluation harness.

The previous version substituted gold labels when the server was offline,
which could report perfect accuracy without evaluating a prediction. This
entry point now uses the real endpoint evaluator and never fabricates scores.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from evaluate_parser_models import DEFAULT_EVAL_FILE, evaluate, load_rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://localhost:8080")
    parser.add_argument("--eval-file", type=Path, default=DEFAULT_EVAL_FILE)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = evaluate(args.base_url, load_rows(args.eval_file), args.timeout)
    print(json.dumps({key: value for key, value in report.items() if key != "cases"}, indent=2))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
