#!/usr/bin/env python3
"""정리(Organize) 프롬프트를 샘플 받아쓰기에 돌려 본다.

키는 환경 변수로만 읽는다. 명령 인자로 넣지 않는다.
  export OPENAI_API_KEY="..."
  export ANTHROPIC_API_KEY="..."   # 없어도 된다. 있는 모델만 호출한다.
  python3 scripts/organize_prompt_eval.py

키가 하나도 없으면 모델을 호출하지 않고, 케이스 구성만 검사한다.
프롬프트는 Tests/VoiceInkTests/prompt_ko_organize_v1.txt (앱에 실리는 글)이다.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES_PATH = ROOT / "scripts" / "organize_eval_cases.jsonl"
PROMPT_PATH = ROOT / "Tests" / "VoiceInkTests" / "prompt_ko_organize_v1.txt"

OPENAI_URL = "https://api.openai.com/v1/chat/completions"
ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
OPENAI_MODEL = "gpt-6-luna"
ANTHROPIC_MODEL = "claude-haiku-5-5"
REQUEST_TIMEOUT = 300


def load_cases():
    cases = []
    for line in CASES_PATH.read_text(encoding="utf-8").splitlines():
        if line.strip():
            cases.append(json.loads(line))
    return cases


def check_case_set(cases):
    errors = []
    by_category = {}
    for case in cases:
        by_category.setdefault(case["category"], []).append(case)
        if not case["input"].strip():
            errors.append(f"{case['id']}: 입력이 비었다")
    banmal = by_category.get("banmal", []) + by_category.get("banmal_quoted", [])
    if len(banmal) != 10:
        errors.append(f"반말 케이스는 10개여야 한다. 지금 {len(banmal)}개")
    quoted = by_category.get("banmal_quoted", [])
    if len(quoted) != 2:
        errors.append(f"인용 존댓말 케이스는 2개여야 한다. 지금 {len(quoted)}개")
    if len(by_category.get("short", [])) != 3:
        errors.append("짧은 말은 3개여야 한다")
    messy = by_category.get("messy", [])
    if len(messy) != 3:
        errors.append("어지러운 말은 3개여야 한다")
    for case in messy:
        count = len(case["input"])
        if not 400 <= count < 700:
            errors.append(f"{case['id']}: 1~2분 분량으로 400~699자여야 한다. 지금 {count}자")
        if case.get("expect_bullets") is not True or case.get("expect_headings") is not False:
            errors.append(f"{case['id']}: 글머리표만 기대해야 한다")
    long_cases = by_category.get("long", [])
    if len(long_cases) != 1:
        errors.append("긴 독백은 1개여야 한다")
    for case in long_cases:
        count = len(case["input"])
        if not 2000 <= count <= 2500:
            errors.append(f"{case['id']}: 2,000~2,500자여야 한다. 지금 {count}자")
        if case.get("expect_bullets") is not True or case.get("expect_headings") is not True:
            errors.append(f"{case['id']}: 소제목과 글머리표를 기대해야 한다")
    for case in banmal:
        if case.get("expect_headings") is not False:
            errors.append(f"{case['id']}: 짧은 반말에 소제목을 기대하면 안 된다")
    return errors


def user_message(transcript):
    return f"<TRANSCRIPT>\n{transcript}\n</TRANSCRIPT>"


def max_tokens(transcript):
    return min(16_000, max(600, len(transcript) * 2))


def post_json(url, headers, body):
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        return json.load(response)


def call_openai(prompt, transcript, api_key):
    payload = post_json(
        OPENAI_URL,
        {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        {
            "model": OPENAI_MODEL,
            "messages": [
                {"role": "system", "content": prompt},
                {"role": "user", "content": user_message(transcript)},
            ],
            "reasoning_effort": "none",
            "max_completion_tokens": max_tokens(transcript),
        },
    )
    content = payload["choices"][0]["message"]["content"]
    if isinstance(content, list):
        return "".join(part.get("text", "") for part in content if isinstance(part, dict))
    return content or ""


def call_anthropic(prompt, transcript, api_key):
    payload = post_json(
        ANTHROPIC_URL,
        {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        {
            "model": ANTHROPIC_MODEL,
            "max_tokens": max_tokens(transcript),
            "system": prompt,
            "messages": [{"role": "user", "content": user_message(transcript)}],
            "thinking": {"type": "disabled"},
            "output_config": {"effort": "low"},
        },
    )
    parts = []
    for block in payload.get("content", []):
        if isinstance(block, dict) and block.get("type") == "text":
            parts.append(block.get("text", ""))
    return "".join(parts)


def masked(text, allowed):
    cleaned = text
    for phrase in allowed:
        if phrase:
            cleaned = cleaned.replace(phrase, "")
    return cleaned


def judge(case, output):
    failures = []
    allowed = case.get("allow_substrings") or []
    visible = masked(output, allowed)
    for required in case.get("required") or []:
        if required not in output:
            failures.append(f"빠짐: {required}")
    for forbidden in case.get("forbidden_substrings") or []:
        if forbidden in visible:
            failures.append(f"말투/금지: {forbidden}")
    bullet = any(line.strip().startswith("- ") for line in output.splitlines())
    heading = any(line.strip().startswith("###") for line in output.splitlines())
    if case.get("expect_bullets") is True and not bullet:
        failures.append("글머리표(- )가 없다")
    if case.get("expect_bullets") is False and bullet:
        failures.append("글머리표가 있으면 안 된다")
    if case.get("expect_headings") is True and not heading:
        failures.append("소제목(###)이 없다")
    if case.get("expect_headings") is False and heading:
        failures.append("소제목이 있으면 안 된다")
    minimum = case.get("min_output_chars")
    if isinstance(minimum, int) and len(output) < minimum:
        failures.append(f"출력이 짧다 ({len(output)}자, 최소 {minimum}자)")
    return failures


def print_inventory(cases):
    print("케이스 구성 (모델을 호출하지 않은 목록)")
    for case in cases:
        print(f"  {case['id']:4} {case['category']:14} {len(case['input']):4}자")


def main():
    cases = load_cases()
    errors = check_case_set(cases)
    if errors:
        print("케이스 구성이 맞지 않는다.")
        for error in errors:
            print(" -", error)
        return 1

    prompt = PROMPT_PATH.read_text(encoding="utf-8")
    if "더 많이 쓴 쪽으로" in prompt:
        print("프롬프트 파일이 옛 정리 규칙이다.")
        return 1

    openai_key = (os.environ.get("OPENAI_API_KEY") or "").strip()
    anthropic_key = (os.environ.get("ANTHROPIC_API_KEY") or "").strip()
    models = []
    if openai_key:
        models.append((OPENAI_MODEL, lambda text, key=openai_key: call_openai(prompt, text, key)))
    if anthropic_key:
        models.append((ANTHROPIC_MODEL, lambda text, key=anthropic_key: call_anthropic(prompt, text, key)))

    print_inventory(cases)
    if not models:
        print()
        print("OPENAI_API_KEY 와 ANTHROPIC_API_KEY 가 없다.")
        print("모델을 호출하지 않았다. 통과/실패 결과는 없다.")
        return 0

    failed = 0
    for model_name, call in models:
        print()
        print(f"== {model_name} ==")
        for case in cases:
            try:
                output = call(case["input"]).strip()
                problems = judge(case, output)
            except urllib.error.HTTPError as error:
                detail = error.read().decode("utf-8", errors="replace")[:500]
                output = ""
                problems = [f"HTTP {error.code}: {detail}"]
            except Exception as error:  # noqa: BLE001 - report any provider failure as a case failure
                output = ""
                problems = [f"{type(error).__name__}: {error}"]
            status = "통과" if not problems else "실패"
            if problems:
                failed += 1
            print(f"[{status}] {case['id']} ({len(output)}자)")
            for problem in problems:
                print(f"    - {problem}")
            print(output)
            print("---")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
