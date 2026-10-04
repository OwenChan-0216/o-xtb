# This file is part of xtb.
#
# Copyright (C) 2019-2021 Sebastian Ehlert
#
# xtb is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# xtb is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with xtb.  If not, see <https://www.gnu.org/licenses/>.

# Find test-drive dependency for testing
testdrive_dep = dependency(
  'test-drive',
  version: '>=0.3',
  fallback: ['test-drive', 'testdrive_dep'],
  required: not meson.is_subproject(),
  default_options: [
    'default_library=static',
    'openmp=false',
  ],
)
# If we do not find test-drive and are a subproject, we just skip testing
if not testdrive_dep.found()
  subdir_done()
endif

tests = [
  'atomlist',
  'bmatrix',
  'coordinationnumber',
  'coulomb',
  'dftd3',
  'dftd4',
  'detrotra',
  'docking',
  'eeq',
  'gfn0',
  'gfn1',
  'gfn2',
  'gfnff',
  'hessian',
  'iff',
  'landscape-api',
  'landscape-settings',
  'landscape-coords',
  'landscape-hessian-update',
  'landscape-optimize-math',
  'landscape-cg',
  'landscape-hessian',
  'landscape-optimize-xtb',
  'landscape-failure',
  'landscape-scan',
  'landscape-vib',
  'landscape-saddle',
  'landscape-path',
  'landscape-irc',
  'landscape-e2e',
  'latticepoint',
  'molecule',
  'model-hessian',
  'oniom',
  'optimizer',
  'dipro',
  'pbc-tools',
  'peeq',
  'random',
  'repulsion',
  'symmetry',
  'tblite',
  'thermo',
  'vertical',
  'wsc',
  'cpx',
]

test_srcs = files(
  'main.f90',
  'molstock.f90',
  #> analytic test potentials shared by the landscape tests
  'landscape_testpot.f90',
  #> PTB as additional test since ending is different
  'test_ptb.F90',
)
foreach t : tests
  test_srcs += files('test_@0@.f90'.format(t.underscorify()))
endforeach

tester = executable(
  'tester',
  sources: test_srcs,
  dependencies: [xtb_dep_static, testdrive_dep],
  fortran_args: [
     '-DWITH_TBLITE=@0@'.format(tblite_dep.found() ? 1 : 0),
     '-DWITH_CPCMX=@0@'.format(cpx_dep.found() ? 1 : 0),
  ],
  link_language: 'fortran',
)

foreach t : tests
  if t == 'landscape-optimize-xtb' or t == 'landscape-scan' or t == 'landscape-vib' or t == 'landscape-e2e'
    # bitwise reproducibility of the `off` restart policy needs a fixed thread
    # count (OpenMP reduction ordering changes the last bits); the scan and
    # frequency suites additionally run 340x faster with one thread (they
    # evaluate many small single points)
    test(t, tester, args: t, suite: 'unit', env: xtbenv + ['OMP_NUM_THREADS=1'])
  else
    test(t, tester, args: t, suite: 'unit', env: xtbenv)
  endif
endforeach
test('ptb', tester, args: 'ptb', suite: 'unit', env: xtbenv)

# some very basic checks to see if the executable reacts at all
test('Argparser print version', xtb_exe, args: '--version', env: xtbenv)
test('Argparser print help', xtb_exe, args: '--help', env: xtbenv)
test('Argparser print license', xtb_exe, args: '--license', env: xtbenv)
test('Argparser no arguments', xtb_exe, should_fail: true, env: xtbenv)
test('GFN2-FF xcontrol', xtb_exe, env: xtbenv, args: [
  '--coffee', '--strict', '--norestart', '--namespace', 'test7',
  '--input', files('../inputs/gfnff.inp'),
])
if host_machine.system() != 'windows'
  test('Info', xtb_exe, env: xtbenv, args: [
    'info',
    files('../../assets/inputs/xyz/taxol.xyz'),
    files('../../assets/inputs/coord/caffeine.coord'),
    files('../../assets/inputs/coord/quartz.3d.coord'),
    files('../../assets/inputs/vasp/ammonia.vasp'),
  ])
endif

# Every landscape check that runs the engine uses one thread: with the default
# thread count the 340x OpenMP anti-scaling of AGENTS.md section 6.8 dominates
# their runtime (PLAN appendix A).  The error branches keep the plain
# environment, they never reach a calculation.
landscape_env = xtbenv + ['OMP_NUM_THREADS=1']

# CLI level smoke test of the new `--lopt` run type.  The water input is
# generated in the build directory with the Python interpreter meson always
# provides (see the root meson.build); the test fails if the minimisation does
# not converge, because a non-converged landscape run reports an error and
# therefore exits with a non-zero status.
h2o_xyz = meson.current_build_dir() / 'landscape_h2o.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("3\\nwater\\nO 0.0 0.0 0.0\\nH 0.0 0.0 0.96\\nH 0.93 0.0 -0.24\\n")',
  h2o_xyz,
  check: true,
)
# the distorted water of `xtb/landscape-native-runtypes-unaffected`: the native
# optimisation has to shorten the 1.30 angstrom O-H bond, so an unoptimised run
# is detectable in the geometry itself
h2o_stretch_xyz = meson.current_build_dir() / 'landscape_h2o_stretch.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("3\\nstretched water\\nO 0.0 0.0 0.0\\nH 0.0 0.0 1.3\\nH 1.3 0.0 -0.4\\n")',
  h2o_stretch_xyz,
  check: true,
)
test('landscape opt', xtb_exe, env: landscape_env, args: [
  h2o_xyz, '--gfn', '2', '--lopt', '--lopt-engine', 'lbfgs',
  '--lopt-level', 'normal', '--norestart', '--namespace', 'landscape1',
])

# CLI level smoke test of the `--lscan` run type: a bidirectional scan of an
# internal coordinate must complete and write its scan log.
test('landscape scan cli', xtb_exe, env: landscape_env, args: [
  h2o_xyz, '--gfn', '2', '--lscan', '--lscan-coord', 'angle',
  '--lscan-atoms', '2,1,3', '--lscan-step', '3', '--lscan-nstep', '3',
  '--lscan-level', 'loose', '--norestart', '--namespace', 'landscape2',
])

# CLI level checks of the landscape suite, mirroring the `cmake -P` scripts of
# test/unit/CMakeLists.txt.  Meson cannot inspect the output of a test, so the
# checks run through `landscape_cli_check.py`, which implements exactly the same
# conditions as the CMake scripts (see the docstring of that file).
landscape_cli_check = files('landscape_cli_check.py')
landscape_cli_dir = meson.current_build_dir()

# the reported TOTAL ENERGY must be the energy of the converged geometry, i.e.
# exactly the value written to xtbopt.xyz
test('landscape opt energy', python, env: landscape_env, args: [
  landscape_cli_check, 'energy', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-energy',
])

# the file namespace of the `--lopt` geometry and trajectory: without
# `--namespace` the names stay `xtbopt.xyz`/`xtb.trj`, and two namespaced runs in
# one directory write (and keep) two different geometry files (mirrors
# `xtb/landscape-opt-namespace`; the stretched input is written by the check)
test('landscape opt namespace', python, env: landscape_env, args: [
  landscape_cli_check, 'optnamespace', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-opt-namespace',
])

# the CLI accuracy (`--acc`) must reach the engine control and change the result
test('landscape opt acc', python, env: landscape_env, args: [
  landscape_cli_check, 'acc', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-acc',
])

# the `--lopt-hessian` selector must reach the engine for every algorithm that
# uses a Hessian, and both backends must converge to the same energy
test('landscape opt hessian', python, env: landscape_env, args: [
  landscape_cli_check, 'hessian', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-hessian',
])

# an unconverged SCC must abort the run with a non-zero status
test('landscape scf failure', python, env: xtbenv, args: [
  landscape_cli_check, 'scf', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-scf',
])

# a scan point whose single point fails must be reported with a non-zero
# status, must not be written as a fabricated zero energy and must not produce
# one frame per requested point (mirrors `xtb/landscape-scan-failed-point`)
# the 340x OpenMP anti-scaling of AGENTS.md section 6.8 applies to this scan
test('landscape scan failed point', python, env: landscape_env, args: [
  landscape_cli_check, 'scanfail', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-scan-fail',
])

# the `--lopt-engine` / `--lopt-level` / `--lopt-hessian` error branches; a
# missing or unknown value must abort with the documented message
test('landscape engine missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'requires an algorithm name', '--gfn', '2', '--lopt', '--lopt-engine',
])
test('landscape engine unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape minimisation algorithm', '--gfn', '2', '--lopt', '--lopt-engine', 'bogus',
])
test('landscape level missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'requires a level name', '--gfn', '2', '--lopt', '--lopt-level',
])
test('landscape level unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape convergence level', '--gfn', '2', '--lopt', '--lopt-level', 'bogus',
])
# the frequency task: the four `--hess` output files, the `res` write-back and
# the read back of the `hessian` file through the file provider
test('landscape vib cli', python, env: landscape_env, args: [
  landscape_cli_check, 'vib', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-vib',
])

# the `hessian` file carries `--namespace` once and is read back by the file
# provider through the same name
# (mirrors `xtb/landscape-vib-namespace`)
test('landscape vib namespace', python, env: landscape_env, args: [
  landscape_cli_check, 'vibnamespace', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-vib-namespace',
])

# the CLI `--etemp` reaches the landscape engine (the `main.F90` sync guard);
# a near-degenerate stretched H2 shifts its only mode by >30 % between 300 K
# and 5000 K (mirrors `xtb/landscape-vib-etemp`)
h2_xyz = meson.current_build_dir() / 'landscape_h2.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("2\\nstretched H2 (2.4 A)\\nH 0.0 0.0 -2.2674600\\nH 0.0 0.0 2.2674600\\n")',
  h2_xyz,
  check: true,
)
test('landscape vib etemp', python, env: landscape_env, args: [
  landscape_cli_check, 'vibetemp', xtb_exe, h2_xyz,
  landscape_cli_dir / 'landscape-cli-vib-etemp',
])

# `$fix` holds the frozen atom for every minimiser, including the RFO one whose
# step is built from the Hessian (mirrors `xtb/landscape-fix-rfo`)
test('landscape fix rfo', python, env: landscape_env, args: [
  landscape_cli_check, 'fix', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-fix',
])

# a landscape run type rejects the xcontrol `$scan` block instead of silently
# performing a different task (mirrors `xtb/landscape-scan-xcontrol`)
test('landscape scan xcontrol', python, env: landscape_env, args: [
  landscape_cli_check, 'scanblock', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-scanblock',
])

# `--lvib` thermochemistry follows the `$thermo` priority rule and agrees with
# `--hess` under the same block (mirrors `xtb/landscape-vib-thermo`)
test('landscape vib thermo', python, env: landscape_env, args: [
  landscape_cli_check, 'thermo', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-thermo',
])

# the rotor (`sthr`) and imaginary (`imagthr`) cutoffs of `$thermo` take effect
# through `--lvib-rotor-cutoff`/`--lvib-imag-cutoff` as well
# (mirrors `xtb/landscape-vib-thermo-knobs`; the second geometry is the bent HCN
# saddle, which has one imaginary mode to invert)
test('landscape vib thermo knobs', python, env: landscape_env, args: [
  landscape_cli_check, 'thermoknobs', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-vib-thermo-knobs',
  meson.current_build_dir() / 'landscape_hcn.xyz',
])

# `$fix` holds the frozen atom for the single ended saddle searches as well
# (mirrors `xtb/landscape-lts-fix`; the input is the bent HCN transition state
# guess whose atom 1 is frozen)
hcn_xyz = meson.current_build_dir() / 'landscape_hcn.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("3\\nbent HCN (transition state guess)\\nH 0.0 1.05 0.0\\nC 0.0 0.0 0.0\\nN 1.156 0.0 0.0\\n")',
  hcn_xyz,
  check: true,
)
test('landscape lts fix', python, env: landscape_env, args: [
  landscape_cli_check, 'saddlefix', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-lts-fix',
])

# the band searches and the reaction path refuse `$fix` instead of moving the
# frozen atoms (mirrors `xtb/landscape-lirc-fix`)
test('landscape lirc fix', python, env: landscape_env, args: [
  landscape_cli_check, 'rejectfix', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-lirc-fix',
])

# `--lscan-max-steps`: a scan without a converged point reports a missing
# minimum (M2 leftovers M-1/M-2)
test('landscape scan max steps', python, env: landscape_env, args: [
  landscape_cli_check, 'maxsteps', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-maxsteps',
])

# `--lscan-hessian` reaches the engine of the scan points
test('landscape scan hessian', python, env: landscape_env, args: [
  landscape_cli_check, 'scanhess', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-scanhess',
])

test('landscape hessian unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape Hessian source', '--gfn', '2', '--lopt', '--lopt-hessian', 'bogus',
])
test('landscape vib odlr', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'ODLR approximation', '--gfn', '2', '--lvib', '--lvib-odlr',
])
test('landscape vib hessian missing file', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'cannot open Hessian file', '--gfn', '2', '--lvib', '--lvib-hessian', 'file',
  '--lvib-hessian-file', 'no_such_file.dat',
])
test('landscape vib hessian unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape Hessian source', '--gfn', '2', '--lvib', '--lvib-hessian', 'bogus',
])
# unusable thermochemical parameters are rejected instead of producing Inf/NaN
# (mirrors `xtb/landscape-vib-temperature-invalid`)
test('landscape vib temperature invalid', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'the thermochemical temperature must be positive',
  '--gfn', '2', '--lvib', '--lvib-temp', '0',
])
# a positive imaginary cutoff silently inverts the flag
# (mirrors `xtb/landscape-vib-imag-cutoff-invalid`)
test('landscape vib imag cutoff invalid', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'the imaginary frequency cutoff must not be positive',
  '--gfn', '2', '--lvib', '--lvib-imag-cutoff', '20',
])
test('landscape scan coord unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape scan coordinate', '--gfn', '2', '--lscan', '--lscan-coord', 'bogus',
])
# the mandatory scan options are named by the flag the caller has to pass
# (CLI redesign sections 8.2 and 17.2): the patterns are the flag names, not the
# old value messages, and the second coordinate is covered by its `2` suffixed
# spelling
# (mirrors `xtb/landscape-scan-nstep-missing` and `xtb/landscape-scan-atom-range`)
test('landscape scan nstep missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'set it with --lscan-nstep', '--gfn', '2', '--lscan', '--lscan-coord', 'distance',
  '--lscan-atoms', '1,2', '--lscan-step', '0.1', '--lscan-nstep', '0',
])
test('landscape scan atom range', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'needs --lscan-atoms', '--gfn', '2', '--lscan', '--lscan-coord', 'distance',
  '--lscan-atoms', '1,9', '--lscan-step', '0.1', '--lscan-nstep', '2',
])
# mirrors `xtb/landscape-scan-step-zero` and `xtb/landscape-scan-coord2-flag`
test('landscape scan step zero', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  '--lscan-step <value> [(]degree[)]', '--gfn', '2', '--lscan', '--lscan-coord', 'angle',
  '--lscan-atoms', '1,2,3', '--lscan-step', '0', '--lscan-nstep', '2',
])
test('landscape scan coord2 flag', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'set it with --lscan-nstep2', '--gfn', '2', '--lscan', '--lscan-ndim', '2', '--lscan-coord', 'distance',
  '--lscan-atoms', '1,2', '--lscan-step', '0.1', '--lscan-nstep', '2', '--lscan-coord2', 'distance',
  '--lscan-atoms2', '2,3', '--lscan-step2', '0.1', '--lscan-nstep2', '0',
])

# Conflicting run types are an error instead of a silent "the first flag wins"
# (mirrors `xtb/landscape-runtype-conflict` and its four siblings; the pattern
# is the rejected flag, so the check fails when the conflict detection or the
# flag names regress).
test('landscape runtype conflict', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-conflict',
  '--lscan would select',
  '--gfn', '2', '--lopt', '--lscan',
])
test('landscape runtype suboption conflict', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-conflict',
  '--lopt-engine would select',
  '--gfn', '2', '--lts', '--lopt-engine', 'bfgs',
])
test('landscape runtype conflict reversed', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-conflict',
  '--lopt would select',
  '--gfn', '2', '--lscan', '--lopt',
])
test('landscape runtype lts lirc', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-conflict',
  '--lirc would select',
  '--gfn', '2', '--lts', '--lirc',
])
test('landscape opt hess conflict', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-conflict',
  '--hess would select',
  '--gfn', '2', '--opt', '--hess',
])
test('landscape vib temp conflict', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-conflict',
  '--lvib-temp would select',
  '--gfn', '2', '--hess', '--lvib-temp', '400',
])
# `--raman` selects the `hess` run type inside `set_elprop`, so it used to
# bypass the conflict detection (mirrors `xtb/landscape-raman-conflict`,
# review finding M1 of `20-stage1-review.md`)
test('landscape raman conflict', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-conflict',
  '--lopt would select',
  '--gfn', '2', '--raman', '0.5', '1000', '--lopt',
])

# `--strict` covers the parser itself and an unknown flag stays a warning
# without it (mirrors `xtb/landscape-strict-unknown`)
test('landscape strict unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'strictunknown', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-strict',
])

# The suite enumeration names are matched case insensitively (mirrors
# `xtb/landscape-enum-case`); the byte comparison of the result files needs a
# fixed thread count (AGENTS.md section 6.1)
test('landscape enum case', python, env: landscape_env, args: [
  landscape_cli_check, 'enumcase', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-enum-case', hcn_xyz,
])

# CLI level smoke test of the `--lts` run type.  The input is a bent HCN, a
# guess for the HCN/HNC transition state (the linear equilibrium geometry is
# already a minimum and converges immediately with zero imaginary modes); the
# search must reach a stationary point with exactly one imaginary mode and
# write `xtbts.xyz` and `xtbts.log` (mirrors `xtb/landscape-ts-prfo`).
hcn_xyz = meson.current_build_dir() / 'landscape_hcn.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("3\\nbent HCN (transition state guess)\\nH 0.0 1.05 0.0\\nC 0.0 0.0 0.0\\nN 1.156 0.0 0.0\\n")',
  hcn_xyz,
  check: true,
)
test('landscape ts prfo', python, env: landscape_env, args: [
  landscape_cli_check, 'ts', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-ts',
])
# The dangerous builtin defaults are echoed as a `[NOTICE]` line and the
# explicit flag silences the notice (CLI redesign sections 8.3 and 17.3);
# mirrors `xtb/landscape-fc-echo`, `xtb/landscape-lirc-default-echo` and
# `xtb/landscape-lts-escape-echo`.  The thread count is fixed because the scan
# case runs the engine (AGENTS.md section 6.8).
test('landscape fc echo', python, env: landscape_env, args: [
  landscape_cli_check, 'echo', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-fc-echo', 'fc',
])
test('landscape lirc default echo', python, env: landscape_env, args: [
  landscape_cli_check, 'echo', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-lirc-echo', 'lirc',
])
test('landscape lts escape echo', python, env: landscape_env, args: [
  landscape_cli_check, 'echo', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-lts-echo', 'lts',
])
# D3 of section 8.3: `--lopt` defaults to `lbfgs`, the native `--opt` runs
# ANCopt, so the active engine is echoed; naming `--lopt-engine` suppresses
# the notice (mirrors `xtb/landscape-lopt-engine-echo`, review finding H1).
test('landscape lopt engine echo', python, env: landscape_env, args: [
  landscape_cli_check, 'echo', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-lopt-echo', 'lopt',
])
# `--help` and the parser must agree in both directions (mirrors
# `xtb/landscape-help-coverage`); the script reads the sources, so it needs no
# environment and no engine.
landscape_help_check = files('landscape_help_check.py')
test('landscape help coverage', python, args: [
  landscape_help_check,
  meson.project_source_root() / 'src' / 'prog' / 'main.F90',
  meson.project_source_root() / 'src' / 'xhelp.f90',
  landscape_cli_dir / 'landscape-help-coverage',
])
# the CLI `--etemp` must reach the transition state engine (the `main.F90`
# sync guard of M4 hard constraint 1; mirrors `xtb/landscape-ts-etemp`)
test('landscape ts etemp', python, env: landscape_env, args: [
  landscape_cli_check, 'tsetemp', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-ts-etemp',
])
# the dimer search locates the same transition state without a Hessian, from
# the deterministic `force` initial axis (mirrors `xtb/landscape-ts-dimer`)
test('landscape ts dimer', python, env: landscape_env, args: [
  landscape_cli_check, 'dimer', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-ts-dimer',
])
# a search that lands on a minimum (0 imaginary modes) must fail with a
# non-zero status (mirrors `xtb/landscape-ts-minimum`, H2); the escape out of a
# minimum is disabled so the input really produces a minimum
hnc_xyz = meson.current_build_dir() / 'landscape_hnc.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("3\\nlinear HNC (a minimum)\\nN 0.0 1.156 0.0\\nC 0.0 0.0 0.0\\nH 0.0 -1.05 0.0\\n")',
  hnc_xyz,
  check: true,
)
test('landscape ts minimum', python, env: landscape_env, args: [
  landscape_cli_check, 'tsminimum', xtb_exe, hnc_xyz,
  landscape_cli_dir / 'landscape-cli-ts-minimum',
])
# the same minimum start succeeds with the default escape walk (MEDIUM-1 of
# `31-m4-review-round2.md`; mirrors `xtb/landscape-ts-escape`)
test('landscape ts escape', python, env: landscape_env, args: [
  landscape_cli_check, 'tsescape', xtb_exe, hnc_xyz,
  landscape_cli_dir / 'landscape-cli-ts-escape',
])
# the `--lts` output files honour `--namespace` (mirrors
# `xtb/landscape-ts-namespace`, M3)
test('landscape ts namespace', python, env: landscape_env, args: [
  landscape_cli_check, 'tsnamespace', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-ts-namespace',
])
test('landscape ts step missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz, landscape_cli_dir / 'landscape-cli-error',
  'The --lts-step flag requires a number', '--gfn', '2', '--lts', '--lts-step',
])
test('landscape ts sccacc missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz, landscape_cli_dir / 'landscape-cli-error',
  'The --lts-sccacc flag requires a number', '--gfn', '2', '--lts', '--lts-sccacc',
])
test('landscape ts step0 missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz, landscape_cli_dir / 'landscape-cli-error',
  'The --lts-step0 flag requires a number', '--gfn', '2', '--lts', '--lts-method',
  'dimer', '--lts-step0',
])
test('landscape ts escape step missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz, landscape_cli_dir / 'landscape-cli-error',
  'The --lts-escape-step flag requires a number', '--gfn', '2', '--lts', '--lts-escape-step',
])
test('landscape ts dimer ninit unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz, landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape dimer initial axis', '--gfn', '2', '--lts', '--lts-method', 'dimer',
  '--lts-ninit', 'bogus',
])
test('landscape ts dimer seed missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz, landscape_cli_dir / 'landscape-cli-error',
  'The --lts-seed flag requires an integer', '--gfn', '2', '--lts', '--lts-method', 'dimer',
  '--lts-seed',
])
test('landscape ts method unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz, landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape transition state method', '--gfn', '2', '--lts', '--lts-method', 'bogus',
])

# CLI checks of the M5 chain-of-states tasks.  The CMake build drives these
# with `xtb/landscape-path-*` scripts; only the AutoNEB insertion cap is
# mirrored here so far, because it is the one branch of the M5 fix round that
# had no automated coverage at all (report 38 L-2, R2-L6).  The ammonia
# inversion is the molecular fixture of the whole path suite.
nh3_up_xyz = meson.current_build_dir() / 'landscape_nh3_up.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("4\\nammonia (N above the H3 plane)\\nN  0.0000000  0.0000000  0.3800000\\nH  0.9400000  0.0000000  0.0000000\\nH -0.4700000  0.8140000  0.0000000\\nH -0.4700000 -0.8140000  0.0000000\\n")',
  nh3_up_xyz,
  check: true,
)
nh3_down_xyz = meson.current_build_dir() / 'landscape_nh3_down.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("4\\nammonia (N below the H3 plane)\\nN  0.0000000  0.0000000 -0.3800000\\nH  0.9400000  0.0000000  0.0000000\\nH -0.4700000  0.8140000  0.0000000\\nH -0.4700000 -0.8140000  0.0000000\\n")',
  nh3_down_xyz,
  check: true,
)
# a run that stops at the AutoNEB insertion depth cap must report the cap in
# the result message and in xtbts.log instead of a bare "converged"
# (mirrors `xtb/landscape-path-autoneb-depth-limit`, report 38 L-2)
test('landscape path autoneb depth limit', python, env: landscape_env, args: [
  landscape_cli_check, 'autonebdepth', xtb_exe, nh3_up_xyz,
  landscape_cli_dir / 'landscape-cli-autoneb-depth', nh3_down_xyz,
])

# `--method` (CLI redesign section 4) is the canonical name of the four
# `--l*` method flags: every pair has to write the same result file, a name of
# another task is refused with a pointer at that task's flag, two different
# values through two flags are an error, `auto` keeps the default and a
# repeated flag keeps the last value (mirrors `xtb/landscape-method`).
test('landscape method', python, env: landscape_env, args: [
  landscape_cli_check, 'method', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-method', hcn_xyz, nh3_up_xyz, nh3_down_xyz,
])

# the four native engines behind `--method` (mirrors
# `xtb/landscape-method-native`); the 501 atom GFN-FF cluster is the only
# fixture that sees the explicit assignment of `ancopt`, because
# `src/main/defaults.f90:42-46` gives a system with more than 500 atoms
# `p_engine_lbfgs`
big_xyz = meson.current_build_dir() / 'landscape_big.xyz'
run_command(
  python, '-c',
  ('import sys\n'
   'lines = ["501", "501 H atoms (the >500 atom engine default)"]\n'
   'for i in range(501):\n'
   '    lines.append("H %d.000000 %d.000000 %d.000000" % ((i % 10) * 3, (i // 10 % 10) * 3, (i // 100) * 3))\n'
   'open(sys.argv[1], "w").write("\\n".join(lines) + "\\n")\n'),
  big_xyz,
  check: true,
)
test('landscape method native', python, env: landscape_env, args: [
  landscape_cli_check, 'methodnative', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-method-native', big_xyz,
])

# every suite method name of `--method` has to reach its task (mirrors
# `xtb/landscape-method-table`): all 18 suite names plus the four `auto` runs
# with the task milestone and the method line of `<ns>.xtbts.log` /
# `<ns>.irc.log`; failures are reported per name
test('landscape method table', python, env: landscape_env, args: [
  landscape_cli_check, 'methodtable', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-method-table', hcn_xyz, nh3_up_xyz,
  nh3_down_xyz,
])

# CLI redesign section 6.3 (stage 2b): the "unified name" flags that the
# stage 2 survey (finding R40) found missing.  Each check runs two flag
# combinations and compares an observable result of the two runs, so the four
# modes are implemented once in `landscape_cli_check.py` and the CMake build
# (`xtb/landscape-opt-knobs` ...) drives the same script.
#
# `--lopt-max-steps`, `--lopt-hess-step`, `--lopt-sccacc` and
# `--lopt-restart` each have to change the minimisation
# (mirrors `xtb/landscape-opt-knobs`)
test('landscape opt knobs', python, env: landscape_env, args: [
  landscape_cli_check, 'optknobs', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-opt-knobs',
])

# `--lscan-hess-step` and `--lscan-sccacc` change the byte image of
# `xtbscan.log` (mirrors `xtb/landscape-scan-knobs`)
test('landscape scan knobs', python, env: landscape_env, args: [
  landscape_cli_check, 'scanknobs', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-scan-knobs',
])

# the canonical `--lts-hess-step` / `--lirc-hess-step` / `--lvib-hess-step`
# names and their older spellings: same value is equivalent (byte identical
# output files that also differ from the default run), a different value is an
# error naming both flags, a repeated flag keeps the last value
# (mirrors `xtb/landscape-hess-step-alias`)
test('landscape hess step alias', python, env: landscape_env, args: [
  landscape_cli_check, 'hessstepalias', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-hess-step-alias', hcn_xyz,
])

# `--lopt-restart` and `--lvib-restart` are read back by the engine and change
# the trajectory and the `hessian` file (mirrors
# `xtb/landscape-restart-knobs`)
test('landscape restart knobs', python, env: landscape_env, args: [
  landscape_cli_check, 'restartknobs', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-restart-knobs',
])

# the effectivity echo of `--l*-hess-step` / `--l*-sccacc` (fix reports 35 and
# 37, close-out report 39): the effective value is echoed from the settings
# object and marked unused when the selected algorithm or Hessian source does
# not consume it.  The notice covers the whole finite difference family, so the
# `*-sccacc-only` cases give the accuracy flag alone (mirrors
# `xtb/landscape-hess-step-used`)
test('landscape hess step used', python, env: landscape_env, args: [
  landscape_cli_check, 'hessused', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-hess-step-used', hcn_xyz, nh3_up_xyz,
  nh3_down_xyz,
])

# `--lvib-restart warm` is not distinguishable from `pin` (fix report T2): the
# `hessian` files are byte identical while `off` differs (mirrors
# `xtb/landscape-lvib-restart-warm`)
test('landscape lvib restart warm', python, env: landscape_env, args: [
  landscape_cli_check, 'lvibrestart', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-lvib-restart-warm',
])

# the native L-BFGS `--opt` path has to write the element symbols intact
# (mirrors `xtb/native-opt-lbfgs-symbols`): upstream copied the geometry with
# an intrinsic `TMolecule` assignment in `src/relaxation_engine.f90`, which
# gfortran 12.2.0 turns into garbage `sym(2:)` bytes; a NUL byte is a valid
# UTF-8 code point, so the check scans bytes and compares the symbol column
# against the input geometry
native_opt_dir = landscape_cli_dir / 'native-opt-lbfgs-symbols'
test('native opt lbfgs symbols', python, env: landscape_env, args: [
  landscape_cli_check, 'nativeoptsym', xtb_exe, h2o_xyz, native_opt_dir,
])

# CLI checks of the M6 IRC task.  `irc` mirrors `xtb/landscape-irc-cli`: the
# input is the bent HCN transition state guess and the check converges it with
# `--lts` first.  The three error branches use the shared `error` mode.
test('landscape irc cli', python, env: landscape_env, args: [
  landscape_cli_check, 'irc', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-irc',
])
# the endpoint knobs really change the result: `--lirc-level`,
# `--lirc-rmsd-end` and the `hpc` default (`46-m6-fix-report.md`, M-1)
test('landscape irc knobs', python, env: landscape_env, args: [
  landscape_cli_check, 'ircknobs', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-irc-knobs',
])
test('landscape irc minimum', python, env: landscape_env, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-error',
  'not a transition state', '--gfn', '2', '--lirc', '--lirc-method', 'gs',
])
test('landscape irc pc', python, env: landscape_env, args: [
  landscape_cli_check, 'ircpc', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-irc-pc',
])
test('landscape irc swap', python, env: landscape_env, args: [
  landscape_cli_check, 'ircswap', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-irc-swap',
])
test('landscape irc method unknown', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-error',
  'Unknown landscape IRC method', '--gfn', '2', '--lirc', '--lirc-method', 'bogus',
])
# a one point DWI surface cannot exist: the capacity is validated
test('landscape irc dwi n', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-error',
  'the IRC DWI surface needs at least two sample points',
  '--gfn', '2', '--lirc', '--lirc-dwi-n', '1',
])
test('landscape irc termination', python, env: landscape_env, args: [
  landscape_cli_check, 'irctermination', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-cli-irc-termination',
])

# ---------------------------------------------------------------------------
# M7: `--ljson` and the end-to-end validation script
# ---------------------------------------------------------------------------
#
# `landscape_e2e_check.py` implements the layered validation of PLAN section
# 9.8 and the machine readable checks of `--ljson`: it parses the document with
# the JSON parser of the standard library, compares every counter against the
# number the task printed, requires two runs to be byte identical and checks
# the namespace prefix.  Meson cannot inspect the output of a test, so the
# conditions live in the script exactly like the ones of
# `landscape_cli_check.py`.
landscape_e2e_check = files('landscape_e2e_check.py')

# The `sp` task has no run type of its own (it is API only) and is covered by
# the unit suite `landscape-e2e` instead.
foreach task : ['opt', 'scan', 'scan2d', 'vib', 'ts', 'irc']
  if task == 'ts' or task == 'irc'
    e2e_input = hcn_xyz
  else
    e2e_input = h2o_xyz
  endif
  test('landscape ljson @0@'.format(task), python, env: landscape_env, args: [
    landscape_e2e_check, 'ljson', xtb_exe, e2e_input,
    landscape_cli_dir / 'landscape-e2e-ljson-@0@'.format(task), task,
  ])
endforeach

# `--ljson` without a landscape run type writes nothing; the no-op has to be
# reported and no document may appear (mirrors `xtb/landscape-ljson-no-runtype`)
test('landscape ljson no runtype', python, env: landscape_env, args: [
  landscape_cli_check, 'ljsonnorun', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cli-ljson-no-runtype',
])

# The product endpoint of the HCN/HNC band searches (same atom order as the
# reactant, HNC on the H-C-N line).  A distinct variable name: `hnc_xyz` above
# is the linear-HNC input of the transition state tests.
hnc_product_xyz = meson.current_build_dir() / 'landscape_hnc_product.xyz'
run_command(
  python, '-c',
  'import sys; open(sys.argv[1], "w").write("3\\nHNC product\\nH 1.0 0.0 0.0\\nC -1.17 0.0 0.0\\nN 0.0 0.0 0.0\\n")',
  hnc_product_xyz,
  check: true,
)
# `--ljson` must produce a valid document for every task method: the eight `ts`
# methods (four band searches among them) and the four `irc` methods.
test('landscape e2e ljson methods', python, env: landscape_env, args: [
  landscape_e2e_check, 'ljson-methods', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-e2e-ljson-methods', hnc_product_xyz,
])
# The sampling point of the `ts` evaluation counter (PLAN section 12.11).
test('landscape e2e ts counters', python, env: landscape_env, args: [
  landscape_e2e_check, 'ts-counters', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-e2e-ts-counters',
])
# The point bookkeeping of a scan, converged and not.
test('landscape e2e scan counters', python, env: landscape_env, args: [
  landscape_e2e_check, 'scan-counters', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-e2e-scan-counters',
])
test('landscape e2e chain', python, env: landscape_env, args: [
  landscape_e2e_check, 'chain', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-e2e-chain',
])
test('landscape e2e chain failure', python, env: landscape_env, args: [
  landscape_e2e_check, 'chain-failure', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-e2e-chain-failure',
])
test('landscape e2e layers', python, env: landscape_env, args: [
  landscape_e2e_check, 'layers', xtb_exe, tester, h2o_xyz,
  landscape_cli_dir / 'landscape-e2e-layers', hcn_xyz,
])
test('landscape e2e maple', python, env: landscape_env, args: [
  landscape_e2e_check, 'maple', xtb_exe, hcn_xyz,
  landscape_cli_dir / 'landscape-e2e-maple',
])

# ---------------------------------------------------------------------------
# CLI redesign stage 3: `--opt`/`--ohess` are executed by the landscape suite
# ---------------------------------------------------------------------------
#
# Mirrors the `xtb/landscape-opt-*` and `xtb/landscape-ohess-*` registrations
# of the CMake build one to one; every assertion uses a token of the *other*
# path, so "the wrong path ran" and "both paths ran" are both failures
# (`docs/_simplify-recon/42-stage3a-impl.md`).
test('landscape opt alias once', python, env: landscape_env, args: [
  landscape_cli_check, 'optalias', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-opt-alias-once',
])
test('landscape opt native exit', python, env: landscape_env, args: [
  landscape_cli_check, 'optnative', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-opt-native-exit',
])
test('landscape opt scanblock', python, env: landscape_env, args: [
  landscape_cli_check, 'optguard', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-opt-scanblock', 'scanblock',
])
# the periodic guard uses the same fixture as the `Info` smoke test above
test('landscape opt pbc', python, env: landscape_env, args: [
  landscape_cli_check, 'optguard', xtb_exe,
  files('../../assets/inputs/coord/quartz.3d.coord'),
  landscape_cli_dir / 'landscape-opt-pbc', 'pbc',
])
test('landscape opt xcontrol', python, env: landscape_env, args: [
  landscape_cli_check, 'optguard', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-opt-xcontrol', 'xcontrol',
])
test('landscape opt xtbopt once', python, env: landscape_env, args: [
  landscape_cli_check, 'optxtbopt', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-opt-xtbopt-once',
])
test('landscape ohess suite once', python, env: landscape_env, args: [
  landscape_cli_check, 'ohesssuite', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-ohess-suite-once',
])
test('landscape ohess native hess', python, env: landscape_env, args: [
  landscape_cli_check, 'ohessnative', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-ohess-native-hess',
])
test('landscape ohess fres bridge', python, env: landscape_env, args: [
  landscape_cli_check, 'ohessbridge', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-ohess-fres-bridge',
])
# stage 3c close-out: `--ohess <LEVEL>` must drive both stages of the chain
# (the minimisation and the frequency analysis), not only the minimisation
test('landscape ohess level axes', python, env: landscape_env, args: [
  landscape_cli_check, 'ohesslevelaxes', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-ohess-level-axes',
])
# stage 3a fix round: the `--opt <LEVEL>` and `--cycles N` bridge, the F3
# refusal and the timing label (redesign sections 3.5/3.10b)
test('landscape opt level bridge', python, env: landscape_env, args: [
  landscape_cli_check, 'optlevel', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-opt-level-bridge',
])
test('landscape cycles map', python, env: landscape_env, args: [
  landscape_cli_check, 'cycles', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-cycles-map',
])
# stage 3c: the level-driven axes `e_tol`, `acc` and the step budget
# (redesign sections 3.5 R5 and 3.10)
test('landscape level axes', python, env: landscape_env, args: [
  landscape_cli_check, 'levelaxes', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-level-axes',
])
# stage 3b: the legacy file contract (redesign section 3.9, R4) and the
# `--ohess` failure path (section 3.9, T2)
test('landscape file contract opt', python, env: landscape_env, args: [
  landscape_cli_check, 'filecontractopt', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-file-contract-opt',
])
test('landscape file contract opt fail', python, env: landscape_env, args: [
  landscape_cli_check, 'filecontractoptfail', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-file-contract-opt-fail',
])
test('landscape file contract vib', python, env: landscape_env, args: [
  landscape_cli_check, 'filecontractvib', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-file-contract-vib',
])
test('landscape file contract namespace', python, env: landscape_env, args: [
  landscape_cli_check, 'filecontractns', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-file-contract-namespace',
])
test('landscape ohess fail', python, env: landscape_env, args: [
  landscape_cli_check, 'ohessfail', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-ohess-fail',
])
# the converse of the compliance contract and the native run types that stage 3a
# accidentally disconnected from their optimisation (review HIGH-1)
test('landscape vib compliance skip', python, env: landscape_env, args: [
  landscape_cli_check, 'vibcomplianceskip', xtb_exe, h2o_xyz,
  landscape_cli_dir / 'landscape-vib-compliance-skip',
])
test('landscape native runtypes unaffected', python, env: landscape_env, args: [
  landscape_cli_check, 'nativetypes', xtb_exe, h2o_stretch_xyz,
  landscape_cli_dir / 'landscape-native-runtypes-unaffected',
])
