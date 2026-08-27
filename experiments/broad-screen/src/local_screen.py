"""Collect the frozen native-wrapper screen on local open reasoning models."""

from __future__ import annotations

import json
import os
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from collect import OLLAMA_CHAT_URL
from experiment import (
    LOCAL_SCREEN_MODELS,
    build_ollama_payload,
    make_local_screen_schedule,
    parse_ollama_payload,
    safe_preview,
    score_trial,
)


OUT = Path("data/local_screen.jsonl")
SCHEDULE_OUT = Path("data/local_screen_schedule.json")
MANIFEST_OUT = Path("data/local_model_manifests.json")
OLLAMA_SHOW_URL = os.environ.get(
    "ODD_NUMBER_OLLAMA_SHOW_URL", "http://127.0.0.1:11434/api/show"
)


def get_manifest(model: str, opener=urllib.request.urlopen) -> dict:
    request = urllib.request.Request(
        OLLAMA_SHOW_URL,
        data=json.dumps({"model": model}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with opener(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def run(trial: dict) -> dict:
    payload = build_ollama_payload(
        trial["model"],
        trial["prompt"],
        system_prompt=None,
        options={
            "temperature": trial["temperature"],
            "top_p": trial["top_p"],
            "seed": trial["sampling_seed"],
            "num_predict": 4096,
        },
    )
    request = urllib.request.Request(
        OLLAMA_CHAT_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=600) as response:
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
    schedule = make_local_screen_schedule()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    SCHEDULE_OUT.write_text(json.dumps(schedule, indent=2), encoding="utf-8")
    manifests = {model: get_manifest(model) for model in LOCAL_SCREEN_MODELS}
    MANIFEST_OUT.write_text(json.dumps(manifests, indent=2), encoding="utf-8")

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

    with OUT.open("a", encoding="utf-8") as handle:
        for index, trial in enumerate(pending, start=1):
            record = run(trial)
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
            handle.flush()
            print(
                f"[{index}/{len(pending)}] {trial['model']} {trial['cell']} -> "
                f"{safe_preview(record['response'])}"
            )


if __name__ == "__main__":
    main()
