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
  if t == 'landscape-optimize-xtb' or t == 'landscape-scan' or t == 'landscape-vib'
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
test('landscape scan nstep missing', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'at least one step is required', '--gfn', '2', '--lscan', '--lscan-coord', 'distance',
  '--lscan-atoms', '1,2', '--lscan-step', '0.1', '--lscan-nstep', '0',
])
test('landscape scan atom range', python, env: xtbenv, args: [
  landscape_cli_check, 'error', xtb_exe, h2o_xyz, landscape_cli_dir / 'landscape-cli-error',
  'outside 1..3', '--gfn', '2', '--lscan', '--lscan-coord', 'distance',
  '--lscan-atoms', '1,9', '--lscan-step', '0.1', '--lscan-nstep', '2',
])
