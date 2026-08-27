"""Run the preregistered Odd Number prompts and append scored JSONL records."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

from experiment import (
    MODELS,
    build_claude_command,
    build_ollama_payload,
    make_schedule,
    parse_claude_payload,
    parse_ollama_payload,
    safe_preview,
    score_trial,
)


OLLAMA_CHAT_URL = os.environ.get(
    "ODD_NUMBER_OLLAMA_URL", "http://127.0.0.1:11434/api/chat"
)


def call_claude(model: str, prompt: str) -> dict:
    completed = subprocess.run(
        build_claude_command(model, prompt),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout)[-2000:]
        raise RuntimeError(f"Claude CLI failed ({completed.returncode}): {detail}")
    return parse_claude_payload(json.loads(completed.stdout), model)


def call_ollama(model: str, prompt: str, system_prompt: str | None = None) -> dict:
    if system_prompt is None:
        # The main preregistered collector uses the shared explicit wrapper.
        from experiment import SYSTEM_PROMPT

        system_prompt = SYSTEM_PROMPT
    body = json.dumps(
        build_ollama_payload(model, prompt, system_prompt=system_prompt)
    ).encode("utf-8")
    request = urllib.request.Request(
        OLLAMA_CHAT_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return parse_ollama_payload(payload, model)


def run_trial(trial: dict, attempts: int = 3) -> dict:
    started = time.perf_counter()
    error = None
    for attempt in range(1, attempts + 1):
        try:
            if trial["provider"] == "claude_cli":
                provider_result = call_claude(trial["model"], trial["prompt"])
            elif trial["provider"] == "ollama":
                provider_result = call_ollama(trial["model"], trial["prompt"])
            else:
                raise ValueError(f"Unsupported provider: {trial['provider']}")
            response = provider_result["response"]
            return {
                **trial,
                "response": response,
                **score_trial(trial, response),
                "provider_metadata": provider_result["provider_metadata"],
                "attempt": attempt,
                "collected_at_utc": datetime.now(timezone.utc).isoformat(),
                "wall_time_seconds": round(time.perf_counter() - started, 3),
            }
        except (OSError, TimeoutError, ValueError, RuntimeError, urllib.error.URLError) as exc:
            error = f"{type(exc).__name__}: {exc}"
            if attempt < attempts:
                time.sleep(1.5 * attempt)
    raise RuntimeError(f"Trial {trial['trial_id']} failed after {attempts} attempts: {error}")


def read_completed_ids(path: Path) -> set[str]:
    if not path.exists():
        return set()
    completed = set()
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                completed.add(json.loads(line)["trial_id"])
            except (json.JSONDecodeError, KeyError) as exc:
                raise ValueError(f"Malformed result line {line_number}: {exc}") from exc
    return completed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--replicates", type=int, default=6)
    parser.add_argument("--seed", type=int, default=20260823)
    parser.add_argument(
        "--phase",
        choices=("all", "replication", "core", "transform"),
        default="all",
    )
    parser.add_argument(
        "--models",
        default=",".join(MODELS),
        help="Comma-separated exact model IDs",
    )
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--out", type=Path, default=Path("data/results.jsonl"))
    parser.add_argument("--schedule-out", type=Path, default=Path("data/schedule.json"))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    selected_models = {model.strip() for model in args.models.split(",") if model.strip()}
    unknown = selected_models.difference(MODELS)
    if unknown:
        raise ValueError(f"Unknown models: {sorted(unknown)}")

    full_schedule = make_schedule(replicates=args.replicates, seed=args.seed)
    schedule = [
        trial
        for trial in full_schedule
        if trial["model"] in selected_models
        and (args.phase == "all" or trial["phase"] == args.phase)
    ]
    completed = read_completed_ids(args.out)
    pending = [trial for trial in schedule if trial["trial_id"] not in completed]

    print(
        json.dumps(
            {
                "scheduled": len(schedule),
                "already_complete": len(schedule) - len(pending),
                "pending": len(pending),
                "models": sorted(selected_models),
                "phase": args.phase,
            },
            indent=2,
        )
    )
    if args.dry_run:
        return

    args.schedule_out.parent.mkdir(parents=True, exist_ok=True)
    args.schedule_out.write_text(
        json.dumps(full_schedule, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)

    failures = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        future_to_trial = {pool.submit(run_trial, trial): trial for trial in pending}
        with args.out.open("a", encoding="utf-8") as handle:
            for index, future in enumerate(as_completed(future_to_trial), start=1):
                trial = future_to_trial[future]
                try:
                    record = future.result()
                except Exception as exc:  # Continue so successful trials remain resumable.
                    failures.append((trial["trial_id"], str(exc)))
                    print(f"FAILED {trial['trial_id']}: {exc}")
                    continue
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                handle.flush()
                print(
                    f"[{index}/{len(pending)}] {trial['model']} {trial['phase']} "
                    f"{trial['cell']} -> {safe_preview(record['response'])}"
                )

    if failures:
        raise RuntimeError(f"{len(failures)} trials failed; rerun to retry them")


if __name__ == "__main__":
    main()
