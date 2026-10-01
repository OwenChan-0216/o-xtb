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
  if t == 'landscape-optimize-xtb'
    # bitwise reproducibility of the `off` restart policy needs a fixed thread
    # count (OpenMP reduction ordering changes the last bits)
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
test('landscape opt', xtb_exe, env: xtbenv, args: [
  h2o_xyz, '--gfn', '2', '--lopt', '--lopt-engine', 'lbfgs',
  '--lopt-level', 'normal', '--norestart', '--namespace', 'landscape1',
])
