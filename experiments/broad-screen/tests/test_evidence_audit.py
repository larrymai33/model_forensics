import json
import sys
import unittest
from pathlib import Path


RESULTS_DIR = Path(__file__).resolve().parents[3] / "results" / "broad-screen"
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from experiment import parse_single_integer
EXPECTED_SOURCES = [
    {"file": "results.jsonl", "cell": "original_even_conflict"},
    {"file": "wrapper_screen.jsonl", "cell": "exact_conflict"},
    {"file": "candidate_screen.sanitized.jsonl", "cell": "exact_conflict"},
    {"file": "local_screen.jsonl", "cell": "exact_conflict"},
]
EXPECTED_MACHINE_COUNTS = {
    "calls": 58,
    "model_ids": 13,
    "strict_valid": 50,
    "strict_valid_odd": 0,
}
EXPECTED_CONTEXT_BREAKDOWN = {
    "explicit_follow_user_system": {"calls": 16, "strict_valid": 15, "strict_valid_odd": 0},
    "neutral_helpful_assistant_system": {"calls": 9, "strict_valid": 9, "strict_valid_odd": 0},
    "wrapper_native_no_caller_system": {"calls": 6, "strict_valid": 6, "strict_valid_odd": 0},
    "codex_minimal_cli_no_caller_system": {"calls": 15, "strict_valid": 15, "strict_valid_odd": 0},
    "local_native_no_caller_system": {"calls": 12, "strict_valid": 5, "strict_valid_odd": 0},
}


def read_jsonl(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def strict_score(record: dict) -> dict:
    value = parse_single_integer(record["response"])
    parity = None if value is None else ("even" if value % 2 == 0 else "odd")
    return {
        "parsed_integer": value,
        "valid_integer": value is not None,
        "output_parity": parity,
    }


class BroadScreenEvidenceAuditTests(unittest.TestCase):
    def test_exact_source_user_message_cohort_reconciles_frozen_machine_counts(self):
        summary = json.loads((RESULTS_DIR / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(
            summary["exact_source_user_message_cohort"]["sources"], EXPECTED_SOURCES
        )

        records = []
        for source in EXPECTED_SOURCES:
            records.extend(
                record
                for record in read_jsonl(RESULTS_DIR / source["file"])
                if record["cell"] == source["cell"]
            )

        scores = [strict_score(record) for record in records]
        for record, score in zip(records, scores, strict=True):
            self.assertEqual(record["parsed_integer"], score["parsed_integer"])
            self.assertEqual(record["valid_integer"], score["valid_integer"])
            self.assertEqual(record["output_parity"], score["output_parity"])

        observed = {
            "calls": len(records),
            "model_ids": len({record["model"] for record in records}),
            "strict_valid": sum(score["valid_integer"] for score in scores),
            "strict_valid_odd": sum(
                score["valid_integer"] and score["output_parity"] == "odd"
                for score in scores
            ),
        }
        self.assertEqual(observed, EXPECTED_MACHINE_COUNTS)
        self.assertEqual(summary["machine_recomputed_counts"], observed)
        self.assertEqual(
            {key: summary[key] for key in EXPECTED_MACHINE_COUNTS}, observed
        )

    def test_wrapper_context_breakdown_is_recomputed_from_frozen_rows(self):
        summary = json.loads((RESULTS_DIR / "summary.json").read_text(encoding="utf-8"))
        grouped = {key: [] for key in EXPECTED_CONTEXT_BREAKDOWN}

        for source in EXPECTED_SOURCES:
            for record in read_jsonl(RESULTS_DIR / source["file"]):
                if record["cell"] != source["cell"]:
                    continue
                if source["file"] == "results.jsonl":
                    key = "explicit_follow_user_system"
                elif source["file"] == "wrapper_screen.jsonl":
                    key = {
                        "follow_user": "explicit_follow_user_system",
                        "neutral": "neutral_helpful_assistant_system",
                        "native": "wrapper_native_no_caller_system",
                    }[record["wrapper"]]
                elif source["file"] == "candidate_screen.sanitized.jsonl":
                    key = (
                        "codex_minimal_cli_no_caller_system"
                        if record["provider"] == "codex_cli"
                        else "neutral_helpful_assistant_system"
                    )
                else:
                    key = "local_native_no_caller_system"
                grouped[key].append(record)

        observed = {
            key: {
                "calls": len(records),
                "strict_valid": sum(
                    strict_score(row)["valid_integer"] for row in records
                ),
                "strict_valid_odd": sum(
                    strict_score(row)["valid_integer"]
                    and strict_score(row)["output_parity"] == "odd"
                    for row in records
                ),
            }
            for key, records in grouped.items()
        }
        self.assertEqual(observed, EXPECTED_CONTEXT_BREAKDOWN)
        self.assertEqual(summary["wrapper_system_context_breakdown"], observed)
        self.assertEqual(sum(cell["calls"] for cell in observed.values()), 58)

    def test_manual_classification_is_labeled_as_same_cohort_not_parser_output(self):
        summary = json.loads((RESULTS_DIR / "summary.json").read_text(encoding="utf-8"))
        manual = summary["manual_raw_response_classification"]
        self.assertEqual(manual["scope"], "same exact source user-message cohort")
        self.assertEqual(manual["clear_even"], 57)
        self.assertEqual(manual["nonanswers"], 1)
        self.assertIn("manual", manual["note"].lower())
        self.assertIn("not parser", manual["note"].lower())


if __name__ == "__main__":
    unittest.main()
