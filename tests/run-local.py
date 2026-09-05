#!/usr/bin/env python3
"""Run provider-mocked Terraform tests without personal state or credentials.

Prerequisite: terraform -chdir=src init -backend=false
Only tracked Terraform helper scripts are copied. No cloud APIs, image builds,
registry pushes, provisioners, or real Terraform plans are executed.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json-output", type=Path, help="Save verbose mock plans for local inspection (synthetic inputs only).")
    args = parser.parse_args()
    if not (SOURCE / ".terraform").is_dir():
        raise SystemExit("Run terraform -chdir=src init -backend=false first.")
    with tempfile.TemporaryDirectory(prefix="oci-oke-local-tests-") as folder:
        sandbox = Path(folder)
        for path in SOURCE.glob("*.tf"):
            shutil.copy2(path, sandbox / path.name)
        for name in [".terraform.lock.hcl"]:
            shutil.copy2(SOURCE / name, sandbox / name)
        # Reuse downloaded provider binaries and modules, not root state.
        (sandbox / ".terraform").symlink_to(SOURCE / ".terraform", target_is_directory=True)
        shutil.copytree(SOURCE / "tests", sandbox / "tests")
        shutil.copytree(SOURCE / "charts", sandbox / "charts")
        for filename in subprocess.check_output(
            ["git", "ls-files", "-z", "src/scripts"], cwd=ROOT
        ).decode().split("\0"):
            if filename:
                target = sandbox / Path(filename).relative_to("src")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / filename, target)
        (sandbox / ".tmp").mkdir()
        (sandbox / ".tmp/qwen_htpasswd").write_text("qwen:test-only-placeholder\n")
        environment = dict(os.environ, CHECKPOINT_DISABLE="1", KUBECONFIG=os.devnull)
        # Ambient TF_VAR values or CLI flags must not inject personal inputs.
        for key in list(environment):
            if key.startswith("TF_VAR_") or key.startswith("TF_CLI_ARGS") or key in {"TF_DATA_DIR", "TF_WORKSPACE"}:
                del environment[key]
        command = ["terraform", f"-chdir={sandbox}", "test", "-no-color"]
        if args.json_output:
            with args.json_output.open("w") as output:
                result = subprocess.run(command + ["-json", "-verbose"], env=environment, stdout=output)
            for line in args.json_output.read_text().splitlines():
                event = json.loads(line)
                if event.get("type") in {"test_run", "test_summary", "diagnostic"}:
                    print(event.get("@message", event["type"]))
            result.check_returncode()
        else:
            subprocess.run(command, env=environment, check=True)


if __name__ == "__main__":
    main()
