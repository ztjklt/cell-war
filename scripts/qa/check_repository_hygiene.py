"""Check staged changes or a CI range without loading unchanged game assets.

Usage: python3 scripts/qa/check_repository_hygiene.py [--base COMMIT]
Historical large files are grandfathered; new or modified blobs are checked.
"""
import argparse
import json
import re
import subprocess
import sys


def git(*args, input=None):
    return subprocess.check_output(["git", *args], input=input)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Compare this commit to HEAD; default: staged changes")
    args = parser.parse_args()
    if args.base:
        base = git("rev-parse", "--verify", args.base + "^{commit}").decode().strip()
        snapshot = "HEAD"
        changed = git("diff", "--no-renames", "--name-only", "--diff-filter=ACM",
                      "-z", base, "HEAD", "--")
    else:
        snapshot = git("write-tree").decode().strip()
        changed = git("diff", "--cached", "--no-renames", "--name-only",
                      "--diff-filter=ACM", "-z", "--")
    # Validate the committed/staged policy, even in a sparse CI checkout.
    policy = json.loads(git("show", snapshot + ":.repo-policy.json"))
    paths = [p.decode() for p in changed.split(b"\0") if p]
    forbidden = [re.compile(p) for p in policy["local_only_patterns"]]
    max_bytes = policy["max_changed_file_bytes"]
    exceptions = policy.get("large_file_exceptions", {})
    errors, objects = [], []
    for path in paths:
        if any(pattern.search(path) for pattern in forbidden):
            errors.append(f"{path}: local process output; archive it outside Git")
        if "\n" in path or "\r" in path:
            errors.append(f"{path!r}: newline in filename is unsupported")
            continue
        objects.append((path, snapshot + ":" + path))
    if objects:
        queries = "\n".join(ref for _, ref in objects) + "\n"
        rows = git("cat-file", "--batch-check=%(objecttype) %(objectsize)",
                   input=queries.encode()).decode().splitlines()
        for (path, _), row in zip(objects, rows, strict=True):
            kind, size = row.split()
            if kind != "blob":
                errors.append(f"{path}: expected a file or symlink, got {kind}")
                continue
            limit = max_bytes
            if path in exceptions:
                exception = exceptions[path]
                if not exception.get("reason", "").strip():
                    errors.append(f"{path}: large-file exception needs a reason")
                limit = exception["max_bytes"]
            if int(size) > limit:
                errors.append(f"{path}: {int(size):,} bytes exceeds {limit:,}; "
                              "reduce/archive it or document a bounded exception")
    for error in errors:
        print("ERROR:", error, file=sys.stderr)
    print(f"Repository hygiene: {len(paths)} added/modified files, "
          f"{len(errors)} violations; default limit {max_bytes // 1024 // 1024} MiB/file")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
