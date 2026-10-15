#!/usr/bin/env python3
"""Run the whole test suite of the takum multiplier with GHDL.

    python3 run_tests.py mul   [N ...]            the multiplier alone
    python3 run_tests.py chain [N ...]            takum -> decoder -> mul -> encoder -> takum
    python3 run_tests.py chain 8 --all-pairs      every possible pair (N <= 10)
    python3 run_tests.py wave                     the Vivado waveform testbench (N = 8)
    python3 run_tests.py demo  [N]                nine readable vectors plus a waveform
    python3 run_tests.py all                      mul + chain + wave, every width
    python3 run_tests.py clean                    delete the build/ folder

Without N, `mul` and `chain` run at N = 8, 12, 16, 24, 32 and 64.

Everything generated (compiled units, vectors, results, waveforms) goes to
build/, next to this script, so the source folders stay clean. The script
prints one PASS or FAIL line per test and a summary at the end; its exit
status is 0 only if every test passed, which is what CI looks at.

This replaces the old Makefile: it does the same thing, works the same way on
Linux, WSL and Windows, and can be read without knowing shell syntax.
"""

import io
import os
import re
import shutil
import subprocess
import sys
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent          # verification/
ROOT = HERE.parent                               # repository root
BUILD = HERE / "build"

sys.path.insert(0, str(HERE))
import takum_model as model                      # noqa: E402  (needs the path above)

# The hardware: compiled in this order, codec first, because each file may
# only use entities that were analysed before it.
RTL = [
    ROOT / "rtl" / "codec" / "predecoder.vhd",
    ROOT / "rtl" / "codec" / "decoder_logarithmic.vhd",
    ROOT / "rtl" / "codec" / "postencoder.vhd",
    ROOT / "rtl" / "codec" / "encoder_logarithmic.vhd",
    ROOT / "rtl" / "takum_mul_log.vhd",
    ROOT / "rtl" / "takum_mul_top.vhd",
]
TB_MUL = HERE / "tb" / "tb_takum_mul_log.vhd"
TB_TOP = HERE / "tb" / "tb_takum_mul_top.vhd"
TB_WAVE = ROOT / "vivado" / "sim" / "tb_takum_mul_wave.vhd"

WIDTHS = [8, 12, 16, 24, 32, 64]
EXACT_LIMIT = 16        # above this, 2^N words are too many to enumerate
ALL_PAIRS_LIMIT = 10    # all 2^N x 2^N pairs: 1 M at N = 10, 16 M at N = 12

results = []            # (label, passed, detail) for the final summary


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def ghdl(*args):
    """Run one GHDL command inside build/ and return (exit code, output)."""
    run = subprocess.run(["ghdl", *args], cwd=BUILD,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return run.returncode, run.stdout


def analyse(*files):
    """Compile VHDL files into the GHDL work library in build/."""
    code, out = ghdl("-a", "--std=08", *[str(f) for f in files])
    if code != 0:
        print(out)
        sys.exit("VHDL analysis failed - see the messages above.")


def record(label, passed, detail):
    results.append((label, passed, detail))
    print(f"{'PASS' if passed else 'FAIL'}  {label:<34} {detail}")


def capture(function, *args):
    """Call a model function and keep what it prints instead of showing it.

    The model prints a line for every file it writes and for every check it
    runs: useful when it is run by hand, noise in a suite that calls it thirty
    times. The text is returned so it can still be shown when something fails.
    """
    text = io.StringIO()
    with redirect_stdout(text):
        result = function(*args)
    return result, text.getvalue()


# ---------------------------------------------------------------------------
# The tests
# ---------------------------------------------------------------------------

def test_mul(n):
    """Multiplier alone: 20,492 vectors on the internal representation."""
    # mul_vectors also cross-checks its own expectations against floating
    # point and returns how many disagree; that must be zero as well.
    cross, text = capture(model.mul_vectors, n, 20000)
    if cross:
        print(text)
        record(f"mul N={n}", False, f"reference model disagrees with itself {cross} times")
        return
    ghdl("-e", "--std=08", "tb_takum_mul_log")
    code, out = ghdl("-r", "--std=08", "tb_takum_mul_log", f"-gN={n}")
    verdict = re.search(r"OK=(\d+) MISMATCHES=(\d+)", out)
    if verdict is None:                       # the simulation never got to the end
        print(out[-800:])
        record(f"mul N={n}", False, "simulation stopped early")
        return
    ok, bad = int(verdict.group(1)), int(verdict.group(2))
    if bad:
        print("\n".join(l for l in out.splitlines() if "MISMATCH:" in l))
    record(f"mul N={n}", bad == 0, f"{ok} vectors, {bad} mismatches")


def test_chain(n, all_pairs=False):
    """Full chain: takum words in, takum words out, checked in Python."""
    exact = n <= EXACT_LIMIT
    if all_pairs:
        capture(model.pairs_exact, n, 0)       # 0 means every possible pair
    elif exact:
        capture(model.pairs_exact, n, 3000)
    else:
        capture(model.pairs_random, n, 3000)

    ghdl("-e", "--std=08", "tb_takum_mul_top")
    code, out = ghdl("-r", "--std=08", "tb_takum_mul_top", f"-gN={n}")
    if code != 0:                             # the check below counts the damage
        errors = [l for l in out.splitlines() if "error" in l.lower()]
        print(f"simulation stopped with an error at N={n}:")
        print("\n".join(errors[-3:]))

    bad, text = capture(model.check_exact if exact else model.check_local, n)
    if bad:
        print(text)                           # the first mismatches, and why
    pairs = sum(1 for _ in open(BUILD / f"pairs_{n}.txt"))
    kind = "all pairs" if all_pairs else ("exact" if exact else "local rounding check")
    record(f"chain N={n} ({kind})", bad == 0, f"{pairs} pairs, {bad} mismatches")


def test_wave():
    """The N = 8 waveform testbench that is meant for Vivado, run under GHDL.

    It checks itself against its own reference model, so all this has to do is
    read its final report. The waveform lands in build/wave_n8.ghw (GTKWave).
    """
    analyse(TB_WAVE)
    ghdl("-e", "--std=08", "tb_takum_mul_wave")
    # Only the testbench and the top of the chain go into the waveform: GHDL
    # 4.1 crashes ("GHDL Bug occurred ... access check failed") when it walks
    # down into the codec's if-else-generate to dump its signals. The
    # simulation itself is unaffected, and Vivado shows every level anyway.
    (BUILD / "wave_signals.txt").write_text(
        "$ version 1.1\n/tb_takum_mul_wave/*\n/tb_takum_mul_wave/dut/*\n")
    code, out = ghdl("-r", "--std=08", "tb_takum_mul_wave", "--wave=wave_n8.ghw",
                     "--read-wave-opt=wave_signals.txt", "--ieee-asserts=disable-at-0")
    demo = re.search(r"DEMO: (\d+) vectors, (\d+) errors", out)
    sweep = re.search(r"SWEEP: (\d+) pairs, (\d+) errors", out)
    if demo is None or sweep is None:
        print(out[-800:])
        record("wave testbench N=8", False, "simulation stopped early")
        return
    bad = int(demo.group(2)) + int(sweep.group(2))
    if bad:
        print("\n".join(l for l in out.splitlines() if "MISMATCH" in l))
    record("wave testbench N=8", bad == 0,
           f"{demo.group(1)} demo + {sweep.group(1)} pairs, {bad} errors")
    print(f"      waveform: {BUILD / 'wave_n8.ghw'}  (open it with GTKWave)")


def demo(n):
    """Nine hand-picked vectors on the multiplier alone, with a waveform."""
    model.demo_vectors(n)
    ghdl("-e", "--std=08", "tb_takum_mul_log")
    code, out = ghdl("-r", "--std=08", "tb_takum_mul_log", f"-gN={n}",
                     f"--wave=demo_{n}.ghw")
    print(out.strip().splitlines()[-1])
    print(f"waveform: {BUILD / f'demo_{n}.ghw'}  (open it with GTKWave)")


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        return 0

    command = argv[1]
    all_pairs = "--all-pairs" in argv
    widths = [int(a) for a in argv[2:] if a.isdigit()] or WIDTHS

    if command == "clean":
        shutil.rmtree(BUILD, ignore_errors=True)
        print("build/ removed")
        return 0

    if shutil.which("ghdl") is None:
        sys.exit("GHDL not found. On Ubuntu or WSL: sudo apt install -y ghdl")
    BUILD.mkdir(exist_ok=True)
    os.chdir(BUILD)        # the model reads and writes its files in the current folder

    if command == "mul":
        analyse(*RTL, TB_MUL)
        for n in widths:
            test_mul(n)
    elif command == "chain":
        if all_pairs and max(widths) > ALL_PAIRS_LIMIT:
            sys.exit(f"--all-pairs is limited to N <= {ALL_PAIRS_LIMIT}: "
                     f"at N = 12 it would be 16 million pairs.")
        analyse(*RTL, TB_TOP)
        for n in widths:
            test_chain(n, all_pairs)
    elif command == "wave":
        analyse(*RTL)
        test_wave()
    elif command == "demo":
        analyse(*RTL, TB_MUL)
        demo(widths[0] if argv[2:] else 16)
        return 0
    elif command == "all":
        analyse(*RTL, TB_MUL, TB_TOP)
        for n in WIDTHS:
            test_mul(n)
        test_chain(8, all_pairs=True)
        for n in WIDTHS:
            test_chain(n)
        test_wave()
    else:
        print(f"unknown command: {command}\n")
        print(__doc__)
        return 2

    failed = [label for label, passed, _ in results if not passed]
    print("-" * 70)
    print(f"{len(results) - len(failed)} of {len(results)} tests passed"
          + (f"; FAILED: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
