#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


def run_one(root: Path, lane_num: int, module: str, waves: int) -> tuple[bool, float]:
    env = os.environ.copy()
    env["LANE_NUM"] = str(lane_num)
    env["ctb"] = module
    env["WAVES"] = str(waves)

    cmd = ["make", "run"]
    print(f"\n=== Running regression: LANE_NUM={lane_num} ===")
    start = time.time()
    ret = subprocess.run(cmd, cwd=root, env=env, check=False)
    elapsed = time.time() - start
    return ret.returncode == 0, elapsed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run quick multi-lane smoke regression for cocotb testbench."
    )
    parser.add_argument(
        "--lanes",
        nargs="+",
        type=int,
        default=[1, 2, 4],
        help="List of LANE_NUM values to run (default: 1 2 4).",
    )
    parser.add_argument(
        "--module",
        default="test_axi2gi",
        help="Cocotb MODULE name (default: test_axi2gi).",
    )
    parser.add_argument(
        "--waves",
        type=int,
        default=0,
        choices=[0, 1],
        help="Enable waveform dump (0/1, default: 0).",
    )
    args = parser.parse_args()

    tb_root = Path(__file__).resolve().parent
    results: list[tuple[int, bool, float]] = []

    for lane_num in args.lanes:
        ok, elapsed = run_one(tb_root, lane_num, args.module, args.waves)
        results.append((lane_num, ok, elapsed))

    print("\n=== Regression Summary ===")
    all_pass = True
    for lane_num, ok, elapsed in results:
        status = "PASS" if ok else "FAIL"
        print(f"LANE_NUM={lane_num:<2}  {status:<4}  {elapsed:7.2f}s")
        if not ok:
            all_pass = False

    if all_pass:
        print("\nAll lane regressions passed.")
        return 0

    print("\nSome lane regressions failed. Check each run output above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
