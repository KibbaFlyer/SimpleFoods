"""Run foundation suites and verify the shared Swift/Python wire contract.

Requires the installed Swift toolchain, Python 3 and the pinned SwiftPM dependencies.
Does not build or launch the iOS app; use xcodebuild for that separate check.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root))
    from tools.catalogue.build import normalized
    from tools.catalogue.core import read_json
    from tools.catalogue.validate import validate

    for version in (1, 2):
        filename = f"fixture-v{version}.json"
        public = root / "data/fixtures" / filename
        bundled = root / "MealTracker/Tests/MealTrackerCoreTests/Fixtures" / filename
        if public.read_bytes() != bundled.read_bytes():
            raise SystemExit(f"Shared fixture differs from Swift test resource: {filename}")

    subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests/catalogue", "-v"],
        cwd=root, check=True,
    )
    with tempfile.TemporaryDirectory(prefix="mealtracker-wire-") as temporary:
        output = Path(temporary) / "swift-fixture-v1.json"
        environment = dict(os.environ, MEALTRACKER_SWIFT_FIXTURE_OUTPUT=str(output))
        subprocess.run(
            ["swift", "test", "--package-path", str(root / "MealTracker")],
            cwd=root, env=environment, check=True,
        )
        registry = read_json(root / "data/source-registry.json")
        swift_pack = normalized(validate(read_json(output), registry))
        source_pack = normalized(validate(read_json(root / "data/fixtures/fixture-v1.json"), registry))
        if swift_pack != source_pack:
            raise SystemExit("Swift encoding changed the fixture's normalized meaning")
    print("Shared fixtures, Python tests, Swift tests, and cross-language validation passed.")


if __name__ == "__main__":
    main()
