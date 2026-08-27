"""Collect the frozen adaptive reasoning-model screen."""

from __future__ import annotations

import json
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

from experiment import (
    build_claude_command,
    build_codex_command,
    make_candidate_schedule,
    parse_claude_payload,
    parse_codex_jsonl,
    safe_preview,
    score_trial,
)


OUT = Path("data/candidate_screen.jsonl")
SCHEDULE_OUT = Path("data/candidate_schedule.json")


def _run_command(command: list[str], provider: str) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=300,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout)[-3000:]
        raise RuntimeError(f"{provider} failed ({completed.returncode}): {detail}")
    return completed


def run(trial: dict, attempts: int = 2) -> dict:
    started = time.perf_counter()
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            if trial["provider"] == "codex_cli":
                completed = _run_command(
                    build_codex_command(trial["model"], trial["prompt"]), "Codex"
                )
                parsed = parse_codex_jsonl(completed.stdout)
            elif trial["provider"] == "claude_cli":
                completed = _run_command(
                    build_claude_command(
                        trial["model"],
                        trial["prompt"],
                        system_prompt=trial["system_prompt"],
                    ),
                    "Claude",
                )
                parsed = parse_claude_payload(
                    json.loads(completed.stdout), trial["model"]
                )
            else:
                raise ValueError(f"Unsupported provider: {trial['provider']}")

            answer = parsed["response"]
            return {
                **trial,
                "response": answer,
                **score_trial(trial, answer),
                "provider_metadata": parsed["provider_metadata"],
                "attempt": attempt,
                "collected_at_utc": datetime.now(timezone.utc).isoformat(),
                "wall_time_seconds": round(time.perf_counter() - started, 3),
            }
        except (OSError, TimeoutError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
            last_error = f"{type(exc).__name__}: {exc}"
            if attempt < attempts:
                time.sleep(2 * attempt)
    raise RuntimeError(
        f"Trial {trial['trial_id']} failed after {attempts} attempts: {last_error}"
    )


def main() -> None:
    schedule = make_candidate_schedule()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    SCHEDULE_OUT.write_text(json.dumps(schedule, indent=2), encoding="utf-8")

    completed_ids = set()
    if OUT.exists():
        completed_ids = {
            json.loads(line)["trial_id"]
            for line in OUT.read_text(encoding="utf-8").splitlines()
            if line.strip()
        }
    pending = [trial for trial in schedule if trial["trial_id"] not in completed_ids]
    print(
        f"scheduled={len(schedule)} complete={len(schedule) - len(pending)} "
        f"pending={len(pending)}"
    )

    failures = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(run, trial): trial for trial in pending}
        with OUT.open("a", encoding="utf-8") as handle:
            for index, future in enumerate(as_completed(futures), start=1):
                trial = futures[future]
                try:
                    record = future.result()
                except Exception as exc:
                    failures.append((trial["trial_id"], str(exc)))
                    print(f"FAILED {trial['trial_id']}: {safe_preview(str(exc))}")
                    continue
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                handle.flush()
                print(
                    f"[{index}/{len(pending)}] {trial['model']} -> "
                    f"{safe_preview(record['response'])}"
                )

    if failures:
        raise RuntimeError(f"{len(failures)} trials failed; rerun to retry them")


if __name__ == "__main__":
    main()
