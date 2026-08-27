#!/usr/bin/env python3
"""Post an xAI review on the current GitHub pull request.

Designed to run in GitHub Actions. Missing XAI_API_KEY skips the job
instead of failing the PR — the review is advisory, not a gate.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.x.ai/v1/chat/completions"
MODEL = os.environ.get("XAI_MODEL", "grok-4-fast")
MAX_DIFF_CHARS = 80_000
SKIP_SUFFIXES = (
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".ttf",
    ".otf",
    ".pbxproj",
    ".xcuserstate",
)
SKIP_PREFIXES = (
    "Branding/",
    "Marketing/",
    "borkmarkr.xcodeproj/",
    "App/Assets.xcassets/",
    "App/Fonts/",
)

SYSTEM = """You review pull requests for bookmarker, a native iOS app (SwiftUI + SwiftData).

Product rules:
- Saving must stay instant. Never gate a save on categorisation, tags, or notes.
- Categorizer is advisory; the user can override before saving.
- Never read UIPasteboard on appear. PasteButton is the paste path.
- Bookmark.stableID is content-derived identity. Do not change its rules.
- Core/ compiles into the app AND the Share Extension. Shared logic stays there.
- App Group group.com.jpwilson.borkmarkr is the store contract.
- Never edit .xcodeproj; project.yml + xcodegen generate.
- DEVELOPMENT_TEAM lives in project.yml.

This PR is about the create flow: tag chips should be recent tags for the
current category AND subcategory (not global frequency), and the topic picker
should be A–Z with search at the top, sticky expansion, and an Add a subtopic
control that still works when the search field has text.

Write a GitHub review in markdown:
1. A short summary (what the diff does, whether it matches the product rules).
2. Bugs and regressions only. Skip style nits.
3. If the diff looks sound, say so — do not invent issues.

Cap the whole review at 700 words. Do not use tables. No secrets."""


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return result.stdout


def should_keep(path: str) -> bool:
    if any(path.startswith(prefix) for prefix in SKIP_PREFIXES):
        return False
    return not path.lower().endswith(SKIP_SUFFIXES)


def filtered_diff(raw: str) -> str:
    chunks: list[str] = []
    current: list[str] = []
    keep = True
    for line in raw.splitlines(keepends=True):
        if line.startswith("diff --git "):
            if current and keep:
                chunks.append("".join(current))
            current = [line]
            parts = line.strip().split(" ")
            path = parts[-1][2:] if parts[-1].startswith("b/") else parts[-1]
            keep = should_keep(path)
        else:
            current.append(line)
    if current and keep:
        chunks.append("".join(current))
    text = "".join(chunks)
    if len(text) > MAX_DIFF_CHARS:
        text = text[:MAX_DIFF_CHARS] + "\n\n[diff truncated]\n"
    return text


def chat(api_key: str, diff: str) -> str:
    body = {
        "model": MODEL,
        "store": False,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {
                "role": "user",
                "content": "Review this pull request diff:\n\n" + (diff or "(empty diff)"),
            },
        ],
    }
    req = urllib.request.Request(
        API,
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            payload = json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        detail = err.read().decode()[:800]
        raise SystemExit(f"xAI HTTP {err.code}: {detail}") from err
    try:
        return payload["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError, TypeError, AttributeError) as err:
        raise SystemExit(f"unexpected xAI payload: {payload!r}") from err


def post_review(owner_repo: str, number: str, body: str) -> None:
    payload = json.dumps({"event": "COMMENT", "body": body}).encode()
    result = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{owner_repo}/pulls/{number}/reviews",
            "--method",
            "POST",
            "--input",
            "-",
        ],
        check=True,
        capture_output=True,
        text=True,
        input=payload.decode(),
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr)


def main() -> int:
    api_key = os.environ.get("XAI_API_KEY", "").strip()
    if not api_key:
        print("XAI_API_KEY is not set — skipping review.")
        print("Add it at Settings → Secrets and variables → Actions.")
        return 0

    event_path = os.environ.get("GITHUB_EVENT_PATH")
    number = os.environ.get("PR_NUMBER")
    if not number and event_path and os.path.exists(event_path):
        with open(event_path, encoding="utf-8") as handle:
            event = json.load(handle)
        number = str(event.get("pull_request", {}).get("number") or "")
    if not number:
        raise SystemExit("could not determine pull request number")

    owner_repo = os.environ.get("GITHUB_REPOSITORY")
    if not owner_repo:
        raise SystemExit("GITHUB_REPOSITORY is not set")

    raw = run(["gh", "pr", "diff", number])
    diff = filtered_diff(raw)
    if not diff.strip():
        post_review(owner_repo, number, "No reviewable source files in this diff.")
        print("posted empty-diff note")
        return 0

    review = chat(api_key, diff)
    header = f"## xAI review (`{MODEL}`)\n\n"
    post_review(owner_repo, number, header + review)
    print(f"posted review on PR #{number}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
