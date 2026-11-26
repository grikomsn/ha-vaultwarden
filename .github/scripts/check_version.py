"""Check the app version before it can reach users.

Rules (see RELEASING.md):
  1. `version` in config.yaml is the Vaultwarden tag from the Dockerfile
     (without `-alpine`), optionally followed by a packaging revision:
     1.37.5 or 1.37.5.2.
  2. CHANGELOG.md has a `## <version>` heading.
  3. With --base <git ref> (pull requests): if anything that ends up in the
     installed app changed (Dockerfile instructions, rootfs/, or config.yaml
     other than `version` and `image`), `version` must be newer than on the base, as
     Home Assistant's Supervisor compares it (AwesomeVersion). A version may
     never go down.

Exit code 1 with GitHub Actions error annotations when a rule is broken.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

import yaml
from awesomeversion import AwesomeVersion

APP = "vaultwarden"
CONFIG = f"{APP}/config.yaml"
DOCKERFILE = f"{APP}/Dockerfile"
CHANGELOG = f"{APP}/CHANGELOG.md"
UPSTREAM_RE = re.compile(
    r"^FROM\s+(?:docker\.io/)?vaultwarden/server:(?P<tag>\d+\.\d+\.\d+)-alpine(?:@|\s|$)", re.M
)
IGNORED_CONFIG_KEYS = {"version", "image"}

errors: list[str] = []


def error(file: str, message: str) -> None:
    errors.append(message)
    print(f"::error file={file}::{message}")


def git_show(ref: str, path: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"], capture_output=True, text=True, check=False
    )
    return result.stdout if result.returncode == 0 else None


def upstream_tag(dockerfile: str) -> str | None:
    match = UPSTREAM_RE.search(dockerfile)
    return match.group("tag") if match else None


def instructions(dockerfile: str) -> list[str]:
    """Dockerfile lines that affect the image (comments and blank lines dropped)."""
    return [
        line.strip()
        for line in dockerfile.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def next_version(base_version: str, base_tag: str | None, tag: str) -> str:
    if tag != base_tag:
        return tag
    parts = base_version.split(".")
    if len(parts) == 4 and parts[3].isdigit():
        return ".".join(parts[:3] + [str(int(parts[3]) + 1)])
    return f"{base_version}.1"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="git ref to compare against (pull requests)")
    args = parser.parse_args()

    config = yaml.safe_load(Path(CONFIG).read_text())
    version = str(config["version"])
    tag = upstream_tag(Path(DOCKERFILE).read_text())
    if tag is None:
        error(DOCKERFILE, "No `FROM docker.io/vaultwarden/server:<x.y.z>-alpine` line found.")
        return 1

    # 1. version = Vaultwarden tag [+ .revision]
    if not re.fullmatch(re.escape(tag) + r"(\.[1-9][0-9]*)?", version):
        error(
            CONFIG,
            f"version {version!r} must be the Vaultwarden tag {tag!r}, "
            f"optionally with a revision like {tag}.1.",
        )

    # 2. changelog entry
    if not re.search(rf"^## {re.escape(version)}\s*$", Path(CHANGELOG).read_text(), re.M):
        error(CHANGELOG, f"Add a `## {version}` section describing this release.")

    # 3. version bump when the app changed
    if args.base:
        base_config_text = git_show(args.base, CONFIG)
        base_dockerfile = git_show(args.base, DOCKERFILE)
        if base_config_text and base_dockerfile:
            base_config = yaml.safe_load(base_config_text)
            base_version = str(base_config["version"])
            base_tag = upstream_tag(base_dockerfile)

            changed = subprocess.run(
                ["git", "diff", "--name-only", args.base, "HEAD", "--", f"{APP}/rootfs"],
                capture_output=True, text=True, check=True,
            ).stdout.split()
            if instructions(base_dockerfile) != instructions(Path(DOCKERFILE).read_text()):
                changed.append(DOCKERFILE)
            strip = lambda c: {k: v for k, v in c.items() if k not in IGNORED_CONFIG_KEYS}
            if strip(config) != strip(base_config):
                changed.append(f"{CONFIG} (options other than version/image)")

            new, old = AwesomeVersion(version), AwesomeVersion(base_version)
            if changed and not new > old:
                suggestion = next_version(base_version, base_tag, tag)
                error(
                    CONFIG,
                    f"The app changed ({', '.join(changed)}) but version is still "
                    f"{version}. Home Assistant only offers an update when the "
                    f"version goes up: set it to {suggestion} and add a "
                    f"`## {suggestion}` CHANGELOG entry.",
                )
            elif new < old:
                error(CONFIG, f"version went down from {base_version} to {version}.")
            print(f"base {base_version} -> head {version}; app changed: {bool(changed)}")

    print(f"version {version}, Vaultwarden {tag}: {'FAIL' if errors else 'OK'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
