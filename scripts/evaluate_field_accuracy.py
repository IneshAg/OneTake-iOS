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

try:
    from evaluate_parser_models import DEFAULT_EVAL_FILE, evaluate, load_rows
except ImportError:
    from scripts.evaluate_parser_models import DEFAULT_EVAL_FILE, evaluate, load_rows


def _forward_offline_eval(eval_file: Path | None, predictions: Path | None, output: Path | None) -> int:
    try:
        from colab import eval_offline_v2
    except ImportError:
        from scripts.colab import eval_offline_v2

    forwarded: list[str] = []
    if eval_file is not None:
        forwarded.extend(["--eval-file", str(eval_file)])
    if predictions is not None:
        forwarded.extend(["--predictions", str(predictions)])
    if output is not None:
        forwarded.extend(["--output", str(output)])
    return eval_offline_v2.main(forwarded)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://localhost:8080")
    parser.add_argument("--eval-file", type=Path, default=None)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--offline-eval",
        action="store_true",
        help="Forward evaluation to scripts/colab/eval_offline_v2.py using --predictions.",
    )
    parser.add_argument(
        "--predictions",
        type=Path,
        help="Predictions JSONL path when --offline-eval is enabled.",
    )
    args = parser.parse_args()

    if args.offline_eval:
        return _forward_offline_eval(args.eval_file, args.predictions, args.output)

    eval_file = args.eval_file if args.eval_file is not None else DEFAULT_EVAL_FILE
    report = evaluate(args.base_url, load_rows(eval_file), args.timeout)
    print(json.dumps({key: value for key, value in report.items() if key != "cases"}, indent=2))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
