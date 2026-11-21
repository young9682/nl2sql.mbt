import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def verify():
    example = Path(__file__).resolve().parent
    repository = example.parents[1]
    build_dir = repository / "_build"
    build_dir.mkdir(exist_ok=True)

    snapshot = (repository / "sqlite/fixtures/orders.db").read_bytes()
    env = os.environ.copy()
    for name in ("NL2SQL_API_KEY", "NL2SQL_ENDPOINT", "NL2SQL_MODEL", "OPENAI_API_KEY"):
        env.pop(name, None)

    with tempfile.TemporaryDirectory(prefix="inventory-acceptance-", dir=build_dir) as temp:
        workspace = Path(temp)
        project = workspace / "inventory-report"
        project.mkdir()
        for source in (example / "moon.mod", example / "moon.pkg", *example.glob("*.mbt")):
            shutil.copyfile(source, project / source.name)
        # The workspace is two directories below the library checkout.
        (workspace / "moon.work").write_text(
            'members = ["../..", "inventory-report"]\n', encoding="utf-8"
        )
        fixture = workspace / "orders.db"
        fixture.write_bytes(snapshot)
        env["NL2SQL_FIXTURE"] = str(fixture)

        subprocess.run(
            ["moon", "test", "--target", "native", "."], cwd=project, env=env, check=True
        )
        output = subprocess.run(
            [
                "moon", "run", "--quiet", "--target", "native", ".", "--",
                str(fixture), "20", "1",
            ],
            cwd=project,
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            encoding="utf-8",
        ).stdout
        expected = {
            "status": "partial",
            "inventory": {
                "columns": ["region", "title", "available"],
                "rows": [[["Text", "east"], ["Text", "Tea"], ["Integer", "5"]]],
                "truncated": True,
            },
        }
        if json.loads(output) != expected:
            raise SystemExit(f"Unexpected inventory report\n{output}")
        if fixture.read_bytes() != snapshot:
            raise SystemExit("The SQLite snapshot changed during verification.")

    print(output.strip())
    print("Independent inventory report verified. SQLite snapshot unchanged.")


if __name__ == "__main__":
    verify()
