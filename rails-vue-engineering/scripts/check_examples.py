#!/usr/bin/env python3
"""Run teaching examples in temporary space; never install dependencies."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(command, cwd, env):
    print("+ " + " ".join(map(str, command)), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ruby", default="ruby", help="Ruby 3.2+ with minitest 5, Active Record/Job 7.2+ and sqlite3")
    parser.add_argument("--node", default="node")
    parser.add_argument("--node-modules", type=Path, required=True, help="Existing modules containing Vue and TypeScript")
    args = parser.parse_args()
    modules = args.node_modules.resolve()
    for name in ("vue", "typescript"):
        if not (modules / name / "package.json").is_file():
            parser.error(f"missing dependency: {name} in {modules}")
    source = Path(__file__).resolve().parents[1] / "examples"
    env = os.environ.copy()
    # Standalone examples do not boot an app or use ambient Minitest plugins.
    env["MT_NO_PLUGINS"] = "1"
    with tempfile.TemporaryDirectory(prefix="rails-vue-examples-") as directory:
        work = Path(directory)
        for path in source.iterdir():
            if path.is_file():
                shutil.copy2(path, work / path.name)
        (work / "package.json").write_text('{"type":"module"}\n')
        (work / "node_modules").symlink_to(modules, target_is_directory=True)
        run([args.ruby, "--version"], work, env)
        run([args.ruby, "ruby-semantics.rb"], work, env)
        run([args.ruby, "transactions.rb"], work, env)
        run([args.node, "--version"], work, env)
        run([args.node, str(modules / "typescript/bin/tsc"), "latest-request.ts",
             "--strict", "--target", "ES2022", "--module", "NodeNext",
             "--moduleResolution", "NodeNext", "--skipLibCheck", "--types", "vue"], work, env)
        run([args.node, "--test", "vue-state.mjs"], work, env)
    print("PASS: example semantics only; no production or agent-behavior claim")


if __name__ == "__main__":
    main()
