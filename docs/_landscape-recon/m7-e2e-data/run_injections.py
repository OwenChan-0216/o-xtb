#!/usr/bin/env python3
"""M7 falsifiability harness: apply one-line injections, run the named tests,
record the outcome, revert (report 49 section 5).

Rule of this project (AGENTS.md section 6, report 34 section 1): before
trusting an injection, show that the mutation *is* the logic it claims to
replace.  Every mutation below is a textual replacement of an exact line, the
old text is required to be present exactly once, and the file is restored from
an in-memory copy in a `finally` block.  The sha256 of every touched file is
printed before and after.
"""
import hashlib
import json
import os
import subprocess
import sys

ROOT = "/home/owenchan/work_path/coding/fortran/xtb"
BUILD = "/tmp/xtb-land/build"
OUT = os.path.join(ROOT, "docs/_landscape-recon/m7-e2e-data/injections")

INJECTIONS = [
    dict(name="json-counter",
         file="src/landscape/types/json.f90",
         old="   call landscape_json_add_counter(self, 'n_eval', result%n_eval)",
         new="   call landscape_json_add_counter(self, 'n_eval', result%n_eval + 1)",
         tests=["xtb/landscape-ljson-opt", "xtb/landscape-ljson-scan", "xtb/landscape-e2e"],
         claim="the JSON counter is the number the task prints"),
    dict(name="json-nondeterministic",
         file="src/landscape/types/json.f90",
         old="      self%message = result%message\n   else\n      self%message = ''",
         new="      block\n         real(wp) :: rnd\n         character(len=16) :: rtxt\n"
             "         call random_number(rnd)\n         write(rtxt,'(f0.8)') rnd\n"
             "         self%message = trim(result%message)//trim(rtxt)\n      end block\n"
             "   else\n      self%message = ''",
         tests=["xtb/landscape-ljson-opt", "xtb/landscape-e2e"],
         claim="the document is byte identical between two runs"),
    dict(name="chain-silent-skip",
         file="test/unit/landscape_e2e_check.py",
         old="    if status == 0:\n        fail(\"a failed chain step exited 0; a caller cannot detect the \"\n"
             "             \"failure\", output)",
         new="    if status == 0 and False:\n        fail(\"a failed chain step exited 0; a caller cannot detect the \"\n"
             "             \"failure\", output)\n"
             "    run(exe, geometry, [\"--gfn\", \"2\", \"--hess\", \"--norestart\"], rundir)",
         tests=["xtb/landscape-e2e-chain-failure"],
         claim="a runner that ignores the exit status is caught"),
    dict(name="thermo-scaling",
         file="src/landscape/vib/thermo.f90",
         old="   set%thermo_fscal = settings%freq_scal",
         new="   set%thermo_fscal = settings%freq_scal*1.01_wp",
         tests=["xtb/landscape-e2e-chain", "xtb/landscape-e2e"],
         claim="the thermochemical parameters really reach the reused model"),
    dict(name="scan-exit-semantics",
         file="src/landscape/tasks/scan.f90",
         old="      call env%error(\"no scan point converged: the reported energy is \"//&",
         new="      call env%warning(\"no scan point converged: the reported energy is \"//&",
         tests=["xtb/landscape-scan-max-steps", "xtb/landscape-scan"],
         claim="a result that is not usable exits non-zero"),
    dict(name="json-scan-points",
         file="src/landscape/tasks/scan.f90",
         old="   call landscape_json_add_counter(doc, 'n_points', profile%n_points)",
         new="   call landscape_json_add_counter(doc, 'n_points', profile%n_points + 1)",
         tests=["xtb/landscape-ljson-scan"],
         claim="the scan counter is the number of written frames"),
    dict(name="json-nondeterministic-writer",
         file="src/landscape/types/json.f90",
         old="   write(unit, '(2x,a,a,a)') '\"message\": \"', &\n"
             "      & json_escape(trim(self%message)), '\",'",
         new="   block\n"
             "      real(wp) :: rndw\n"
             "      character(len=24) :: rtxtw\n"
             "      call random_number(rndw)\n"
             "      write(rtxtw,'(f0.8)') rndw\n"
             "      write(unit, '(2x,a,a,a,a)') '\"message\": \"', trim(rtxtw), &\n"
             "         & json_escape(trim(self%message)), '\",'\n"
             "   end block",
         tests=["xtb/landscape-ljson-opt", "xtb/landscape-e2e"],
         claim="the writer itself is deterministic (the complementary injection:"
               " a value fixed at build time cannot be caught by two writes of"
               " the same document)"),
]


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def build():
    p = subprocess.run(["cmake", "--build", BUILD, "-j"], cwd=ROOT,
                       capture_output=True, text=True)
    return p.returncode, p.stdout[-800:] + p.stderr[-800:]


def ctest(names):
    env = dict(os.environ, OMP_NUM_THREADS="1")
    result = {}
    for name in names:
        p = subprocess.run(["ctest", "--test-dir", BUILD, "-R", "^" + name + "$",
                            "--output-on-failure"], capture_output=True,
                           text=True, env=env)
        text = p.stdout + p.stderr
        result[name] = {"exit": p.returncode, "red": p.returncode != 0,
                        "tail": "\n".join(text.splitlines()[-12:]),
                        "output": text}
    return result


def main():
    os.makedirs(OUT, exist_ok=True)
    report = {}
    for inj in INJECTIONS:
        path = os.path.join(ROOT, inj["file"])
        original = open(path).read()
        before = sha(path)
        assert original.count(inj["old"]) == 1, \
            "%s: the old text is not unique" % inj["name"]
        mutated = original.replace(inj["old"], inj["new"])
        entry = {"file": inj["file"], "claim": inj["claim"],
                 "sha_before": before, "tests": inj["tests"]}
        try:
            open(path, "w").write(mutated)
            code, log = build()
            entry["build"] = code
            entry["compiled"] = "Building Fortran object" in log
            if code != 0:
                entry["build_tail"] = log
                entry["outcome"] = "BUILD FAILED"
            else:
                entry["results"] = ctest(inj["tests"])
                entry["outcome"] = "red" if all(
                    v["red"] for v in entry["results"].values()) else (
                        "partly red" if any(v["red"] for v in
                                            entry["results"].values())
                        else "GREEN (no test caught it)")
        finally:
            open(path, "w").write(original)
            after = sha(path)
            entry["sha_after"] = after
            entry["restored"] = (after == before)
            code, _ = build()
            entry["rebuild"] = code
        report[inj["name"]] = entry
        print("%-22s %s  restored=%s" % (inj["name"], entry["outcome"],
                                         entry["restored"]))
        for name, r in entry.get("results", {}).items():
            print("    %-40s exit=%d %s" % (name, r["exit"],
                                            "RED" if r["red"] else "green"))
    json.dump(report, open(os.path.join(OUT, "injections.json"), "w"),
              indent=1, sort_keys=True)
    # baseline after the injections
    print("baseline after revert:",
          {k: v["exit"] for k, v in ctest(
              ["xtb/landscape-ljson-opt", "xtb/landscape-ljson-scan",
               "xtb/landscape-e2e-chain", "xtb/landscape-e2e-chain-failure",
               "xtb/landscape-scan-max-steps", "xtb/landscape-e2e",
               "xtb/landscape-scan"]).items()})


if __name__ == "__main__":
    main()
