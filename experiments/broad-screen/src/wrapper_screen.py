"""Collect the frozen adaptive system-wrapper screen for gpt-oss-120b."""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

from collect import OLLAMA_CHAT_URL
from experiment import (
    build_ollama_payload,
    make_wrapper_schedule,
    parse_ollama_payload,
    safe_preview,
    score_trial,
)

import urllib.request


OUT = Path("data/wrapper_screen.jsonl")
SCHEDULE_OUT = Path("data/wrapper_schedule.json")


def run(trial: dict) -> dict:
    payload = build_ollama_payload(
        trial["model"], trial["prompt"], system_prompt=trial["system_prompt"]
    )
    request = urllib.request.Request(
        OLLAMA_CHAT_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        raw = json.loads(response.read().decode("utf-8"))
    parsed = parse_ollama_payload(raw, trial["model"])
    answer = parsed["response"]
    return {
        **trial,
        "response": answer,
        **score_trial(trial, answer),
        "provider_metadata": parsed["provider_metadata"],
        "collected_at_utc": datetime.now(timezone.utc).isoformat(),
    }


def main() -> None:
    schedule = make_wrapper_schedule()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    SCHEDULE_OUT.write_text(json.dumps(schedule, indent=2), encoding="utf-8")
    completed = set()
    if OUT.exists():
        completed = {
            json.loads(line)["trial_id"]
            for line in OUT.read_text(encoding="utf-8").splitlines()
            if line.strip()
        }
    pending = [trial for trial in schedule if trial["trial_id"] not in completed]
    print(f"scheduled={len(schedule)} complete={len(completed)} pending={len(pending)}")
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(run, trial): trial for trial in pending}
        with OUT.open("a", encoding="utf-8") as handle:
            for index, future in enumerate(as_completed(futures), start=1):
                trial = futures[future]
                record = future.result()
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                handle.flush()
                print(
                    f"[{index}/{len(pending)}] {trial['wrapper']} {trial['cell']} "
                    f"-> {safe_preview(record['response'])}"
                )


if __name__ == "__main__":
    main()
