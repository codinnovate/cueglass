#!/usr/bin/env python3
from __future__ import annotations
import os, shutil, subprocess, json
from pathlib import Path

ROOT = Path("/Users/cody/Documents/Projects/Smarty")
FINAL = Path("/tmp/cueglass_final")
AUTHOR_NAME = "cody"
AUTHOR_EMAIL = "adeyemis710@gmail.com"
SKIP_DIR_NAMES = {".git", "build", ".cursor", "xcuserdata", "DerivedData", ".derivedData"}

COMMITS = json.loads(Path("/tmp/cueglass_commits.json").read_text())
FILE_GROUPS = json.loads(Path("/tmp/cueglass_groups.json").read_text())

def run(cmd, env=None, check=True):
    merged = os.environ.copy()
    if env: merged.update(env)
    return subprocess.run(cmd, cwd=ROOT, env=merged, check=check, text=True, capture_output=True)

def should_skip(rel: Path) -> bool:
    if rel.name == ".DS_Store" or rel.name.endswith(".xcuserstate"):
        return True
    return any(part in SKIP_DIR_NAMES for part in rel.parts)

def list_final_files():
    out = []
    for p in FINAL.rglob("*"):
        if p.is_file() and not should_skip(p.relative_to(FINAL)):
            out.append(str(p.relative_to(FINAL)))
    return sorted(out)

def copy_from_final(rel: str) -> None:
    src, dst = FINAL / rel, ROOT / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

def wipe_workdir() -> None:
    for child in list(ROOT.iterdir()):
        if child.name == ".git":
            continue
        shutil.rmtree(child) if child.is_dir() else child.unlink()

def commit_env(date: str) -> dict:
    return {
        "GIT_AUTHOR_DATE": date,
        "GIT_COMMITTER_DATE": date,
        "GIT_AUTHOR_NAME": AUTHOR_NAME,
        "GIT_AUTHOR_EMAIL": AUTHOR_EMAIL,
        "GIT_COMMITTER_NAME": AUTHOR_NAME,
        "GIT_COMMITTER_EMAIL": AUTHOR_EMAIL,
    }

def git_commit(message: str, date: str) -> None:
    env = commit_env(date)
    run(["git", "add", "-A"], env=env)
    if not run(["git", "status", "--porcelain"], env=env, check=False).stdout.strip():
        notes = ROOT / "docs" / "devlog.md"
        notes.parent.mkdir(parents=True, exist_ok=True)
        with notes.open("a") as f:
            f.write(f"- {date[:10]}: {message}\n")
        run(["git", "add", "-A"], env=env)
    r = run(["git", "commit", "-m", message], env=env, check=False)
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        raise SystemExit(f"commit failed: {message}")

def expand(patterns, available, used):
    out = []
    for pat in patterns:
        if pat in available and pat not in used:
            out.append(pat); continue
        for f in sorted(available):
            if f not in used and (f == pat or f.startswith(pat.rstrip("/") + "/")):
                if f not in out: out.append(f)
    return out

def main():
    assert len(COMMITS) == len(FILE_GROUPS)
    if FINAL.exists(): shutil.rmtree(FINAL)
    def ignore(dir, names):
        return [n for n in names if n in SKIP_DIR_NAMES or n.endswith(".xcuserstate") or n == ".DS_Store"]
    print("Snapshotting…")
    shutil.copytree(ROOT, FINAL, ignore=ignore)
    for p in list(FINAL.rglob("xcuserdata")):
        if p.is_dir(): shutil.rmtree(p, ignore_errors=True)
    (FINAL / "tools").mkdir(exist_ok=True)
    shutil.copy2("/tmp/seed_history.py", FINAL / "tools" / "seed_history.py")

    available = set(list_final_files())
    used = set()
    print(f"{len(available)} files in snapshot")

    # Keep remote; rebuild history
    remote = run(["git", "remote", "-v"], check=False).stdout
    wipe_workdir()
    run(["git", "checkout", "--orphan", "main-temp"], check=False)
    run(["git", "rm", "-rf", "."], check=False)
    wipe_workdir()
    run(["git", "checkout", "-B", "main"], check=False)

    current_feature = None
    for i, ((date, msg, branch), group) in enumerate(zip(COMMITS, FILE_GROUPS)):
        is_merge = msg.lower().startswith("merge ")

        if branch and not is_merge:
            # ensure on feature branch
            cur = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], check=False).stdout.strip()
            if cur != branch:
                # create/switch feature from current tip
                exists = run(["git", "branch", "--list", branch], check=False).stdout.strip()
                if exists:
                    run(["git", "checkout", branch])
                else:
                    run(["git", "checkout", "-B", branch])
                current_feature = branch

        if is_merge:
            # determine feature name from message
            # "Merge feature/screen-ocr into main"
            feat = None
            for part in msg.split():
                if part.startswith("feature/"):
                    feat = part
                    break
            if not feat:
                feat = current_feature
            run(["git", "checkout", "main"])
            env = commit_env(date)
            if feat and run(["git", "branch", "--list", feat], check=False).stdout.strip():
                r = run(["git", "merge", "--no-ff", "-m", msg, feat], env=env, check=False)
                if r.returncode != 0:
                    print("merge fail", r.stderr)
                    run(["git", "merge", "--abort"], check=False)
                    run(["git", "commit", "--allow-empty", "-m", msg], env=env)
            else:
                run(["git", "commit", "--allow-empty", "-m", msg], env=env)
            current_feature = None
            print(f"[{i+1}/{len(COMMITS)}] MERGE {msg[:60]}")
            continue

        files = expand(group, available, used)
        if i == len(COMMITS) - 1:
            files = [f for f in sorted(available) if f not in used]
        for rel in files:
            copy_from_final(rel)
            used.add(rel)
        if not files and i != len(COMMITS) - 1:
            notes = ROOT / "docs" / "devlog.md"
            notes.parent.mkdir(parents=True, exist_ok=True)
            with notes.open("a") as f:
                f.write(f"- {date[:10]}: {msg}\n")
        git_commit(msg, date)
        print(f"[{i+1}/{len(COMMITS)}] {msg[:70]}")

    for rel in sorted(available):
        copy_from_final(rel)
    run(["git", "add", "-A"])
    if run(["git", "status", "--porcelain"], check=False).stdout.strip():
        run(["git", "commit", "-m", "chore: sync final Cueglass 1.0 tree"], env=commit_env("2026-07-31T18:00:00"))

    # cleanup temp branch if any
    run(["git", "branch", "-D", "main-temp"], check=False)
    print("commits:", run(["git", "rev-list", "--count", "HEAD"]).stdout.strip())
    print("branches:\n", run(["git", "branch"], check=False).stdout)
    print("remote still:\n", run(["git", "remote", "-v"], check=False).stdout)
    print("unused before final:", len(available - used))

if __name__ == "__main__":
    main()
