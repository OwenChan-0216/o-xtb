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

# allocate dir
set(dir "${CMAKE_CURRENT_SOURCE_DIR}")

# collect source files
set(
  tests
  "atomlist"
  "bmatrix"
  "coordinationnumber"
  "coulomb"
  "dftd3"
  "dftd4"
  "detrotra"
  "docking"
  "eeq"
  "gfn0"
  "gfn1"
  "gfn2"
  "gfnff"
  "hessian"
  "iff"
  "landscape-api"
  "landscape-settings"
  "landscape-coords"
  "landscape-hessian-update"
  "landscape-optimize-math"
  "landscape-cg"
  "landscape-hessian"
  "landscape-optimize-xtb"
  "landscape-failure"
  "latticepoint"
  "molecule"
  "model-hessian"
  "oniom"
  "optimizer"
  "dipro"
  "pbc-tools"
  "peeq"
  "random"
  "repulsion"
  "symmetry"
  "tblite"
  "thermo"
  "vertical"
  "wsc"
  "cpx"
)

set(
  test-srcs
  "main.f90"
  "molstock.f90"
  "landscape_testpot.f90"
)

foreach(t IN LISTS tests)
  string(MAKE_C_IDENTIFIER ${t} t) 
  list(APPEND test-srcs "test_${t}.f90")
endforeach()
# add PTB explicitly since it is not part of the tests list (different ending)
list(APPEND test-srcs "test_ptb.F90")


# executable
add_executable(
  "${PROJECT_NAME}-tester"
  "${test-srcs}"
)

target_link_libraries(
  "${PROJECT_NAME}-tester"
  PRIVATE
  "lib-${PROJECT_NAME}-static" # static xtb
  "test-drive::test-drive"     # testing framework
)

if(NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/include")
  file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include")
endif()

set_target_properties(
  "${PROJECT_NAME}-tester"
  PROPERTIES
  Fortran_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include"
)

# test-drive 
foreach(t IN LISTS tests)
  add_test("${PROJECT_NAME}/${t}" "${PROJECT_NAME}-tester" "${t}")
  set_tests_properties(
    "${PROJECT_NAME}/${t}"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR}"
  )
endforeach()
# The GFN2 determinism probe asserts bitwise reproducibility of the `off`
# restart policy, which only holds for a fixed thread count (OpenMP reduction
# ordering changes the last bits, see docs/_landscape-recon/07-*.md section 2).
set_tests_properties(
  "${PROJECT_NAME}/landscape-optimize-xtb"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"
)
# add PTB explicitly since it is not part of the tests list
add_test("${PROJECT_NAME}/ptb" "${PROJECT_NAME}-tester" "ptb")
set_tests_properties(
  "${PROJECT_NAME}/ptb"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR}"
)

# xtb 
set(XTB-EXE "${PROJECT_BINARY_DIR}/${PROJECT_NAME}")

add_test("xtb/Argparser_print_version" ${XTB-EXE} --version)
add_test("xtb/Argparser_print_help" ${XTB-EXE} --help)
add_test("xtb/Argparser_print_license" ${XTB-EXE} --license)
add_test("xtb/Info" ${XTB-EXE} info
  "${PROJECT_SOURCE_DIR}/assets/inputs/coord/caffeine.coord"
  "${PROJECT_SOURCE_DIR}/assets/inputs/coord/quartz.3d.coord"
  "${PROJECT_SOURCE_DIR}/assets/inputs/vasp/ammonia.vasp"
  "${PROJECT_SOURCE_DIR}/assets/inputs/xyz/taxol.xyz"
)
add_test("xtb/Singlepoint" ${XTB-EXE} --coffee --strict --norestart --namespace test1)
add_test("xtb/IP/EA" ${XTB-EXE} --coffee --gfn 2 --vipea --strict --norestart --namespace test2)
add_test("xtb/GFN0-xTB" ${XTB-EXE} --coffee --gfn 0 --strict --norestart --namespace test3)
add_test("xtb/GFN1-xTB" ${XTB-EXE} --coffee --gfn 1 --strict --norestart --namespace test4)
add_test("xtb/GFN2-xTB/GBSA" ${XTB-EXE} --coffee --gfn 2 --strict --gbsa h2o --norestart --namespace test5)
add_test("xtb/GFN2-FF" ${XTB-EXE} --coffee --gfnff --strict --norestart --namespace test6)
add_test("xtb/GFN2-FF/xcontrol" ${XTB-EXE} --coffee --strict --norestart --namespace test7
  --input "${PROJECT_SOURCE_DIR}/test/inputs/gfnff.inp")

# Landscape suite: CLI level smoke test of the new `--lopt` run type.
#
# The water input is generated in the build directory (the repository stays
# free of test data) and the run is driven by a small CMake script, because a
# plain add_test() can only observe the exit status while the smoke test must
# also check that the optimisation converged and wrote its output files.
set(LANDSCAPE-H2O "${CMAKE_CURRENT_BINARY_DIR}/landscape_h2o.xyz")
file(WRITE "${LANDSCAPE-H2O}"
  "3\nwater\nO  0.0000000  0.0000000  0.0000000\n"
  "H  0.0000000  0.0000000  0.9600000\n"
  "H  0.9300000  0.0000000 -0.2400000\n")
set(LANDSCAPE-RUNDIR "${CMAKE_CURRENT_BINARY_DIR}/landscape-cli")
file(MAKE_DIRECTORY "${LANDSCAPE-RUNDIR}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_check.cmake" [=[
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lopt --lopt-engine lbfgs
          --lopt-level normal --norestart --namespace landscape1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lopt terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "landscape minimisation did not converge\n${output}")
endif()
foreach(name "xtbopt.xyz" "xtb.trj")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
]=])
add_test("xtb/landscape-opt"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${LANDSCAPE-RUNDIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_check.cmake")

# Landscape suite: the reported TOTAL ENERGY must be the energy of the
# converged geometry, i.e. exactly the value written to xtbopt.xyz.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_energy.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lopt --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lopt terminated with status ${status}\n${output}")
endif()
string(REGEX MATCH "TOTAL ENERGY +(-?[0-9]+\\.[0-9]+)" _ "${output}")
set(energy_stdout "${CMAKE_MATCH_1}")
file(READ "${RUNDIR}/xtbopt.xyz" xyzfile)
string(REGEX MATCH "energy: +(-?[0-9]+\\.[0-9]+)" _ "${xyzfile}")
set(energy_xyz "${CMAKE_MATCH_1}")
if(NOT energy_stdout)
  message(FATAL_ERROR "no TOTAL ENERGY in the output\n${output}")
endif()
if(NOT energy_stdout STREQUAL energy_xyz)
  message(FATAL_ERROR
    "TOTAL ENERGY (${energy_stdout}) differs from xtbopt.xyz (${energy_xyz})")
endif()
]=])
add_test("xtb/landscape-opt-energy"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-energy
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_energy.cmake")

# Landscape suite: the CLI accuracy (`--acc`) must reach the engine control.
#
# The engine writes `landscape_engine_control%acc` into the calculator, so
# without the sync in `xtbMain` the run would fall back to the default
# accuracy and reproduce the plain `--lopt` result bit for bit.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_acc.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
function(run_case args suffix)
  file(REMOVE "${RUNDIR}/xtbopt.xyz")
  separate_arguments(arg_list UNIX_COMMAND "${args}")
  execute_process(
    COMMAND "${EXE}" "${INPUT}" --gfn 2 --lopt --norestart ${arg_list}
    WORKING_DIRECTORY "${RUNDIR}"
    RESULT_VARIABLE status
    OUTPUT_VARIABLE output
    ERROR_VARIABLE output
  )
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "xtb --lopt ${args} failed with status ${status}\n${output}")
  endif()
  file(READ "${RUNDIR}/xtbopt.xyz" xyzfile)
  string(REGEX MATCH "energy: [^\n]*" line "${xyzfile}")
  set(${suffix}_result "${line}" PARENT_SCOPE)
  string(REGEX MATCH "landscape engine: SCC accuracy +([0-9.]+)" _ "${output}")
  set(${suffix}_acc "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()
run_case("" default)
run_case("--acc 0.05" acc05)
if(NOT default_acc STREQUAL "1.000000")
  message(FATAL_ERROR
    "the default run did not report the default accuracy (${default_acc})")
endif()
if(NOT acc05_acc STREQUAL "0.050000")
  message(FATAL_ERROR
    "--acc 0.05 did not reach the engine control (reported ${acc05_acc})")
endif()
if(default_result STREQUAL acc05_result)
  message(FATAL_ERROR
    "--acc 0.05 had no effect on the --lopt result (${default_result})")
endif()
]=])
add_test("xtb/landscape-opt-acc"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-acc
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_acc.cmake")

# Landscape suite: an unconverged SCC must lead to a non-zero exit status.
#
# The SCC iteration count is forced to one with an xcontrol file; the run must
# abort with a non-zero status and must not report a converged landscape run.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_scf_fail.inp"
  "$scc\n maxiterations=1\n$end\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scf.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lopt --input "${XCONTROL}" --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(status EQUAL 0)
  message(FATAL_ERROR "the unconverged SCC did not fail the run\n${output}")
endif()
if(output MATCHES "landscape: converged")
  message(FATAL_ERROR "a converged landscape run was reported\n${output}")
endif()
]=])
add_test("xtb/landscape-scf-failure"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DXCONTROL=${CMAKE_CURRENT_BINARY_DIR}/landscape_scf_fail.inp
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-scf
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scf.cmake")

# Landscape suite: the `--lopt-engine` / `--lopt-level` error branches.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
separate_arguments(arg_list UNIX_COMMAND "${ARGS}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" ${arg_list}
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(status EQUAL 0)
  message(FATAL_ERROR "expected a non-zero exit for '${ARGS}'\n${output}")
endif()
if(NOT output MATCHES "${PATTERN}")
  message(FATAL_ERROR "missing '${PATTERN}' in the output of '${ARGS}'\n${output}")
endif()
]=])
set(LANDSCAPE-ERROR-DIR "${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error")
add_test("xtb/landscape-engine-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lopt --lopt-engine"
  "-DPATTERN=requires an algorithm name"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-engine-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lopt --lopt-engine bogus"
  "-DPATTERN=Unknown landscape minimisation algorithm"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-level-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lopt --lopt-level"
  "-DPATTERN=requires a level name"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-level-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lopt --lopt-level bogus"
  "-DPATTERN=Unknown landscape convergence level"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

set_tests_properties(
  "xtb/Singlepoint"
  "xtb/GFN0-xTB"
  "xtb/IP/EA"
  "xtb/GFN1-xTB"
  "xtb/GFN2-xTB/GBSA"
  "xtb/GFN2-FF"
  "xtb/GFN2-FF/xcontrol"
  "xtb/landscape-opt"
  "xtb/landscape-opt-energy"
  "xtb/landscape-opt-acc"
  "xtb/landscape-scf-failure"
  "xtb/landscape-engine-missing"
  "xtb/landscape-engine-unknown"
  "xtb/landscape-level-missing"
  "xtb/landscape-level-unknown"
  PROPERTIES
  ENVIRONMENT XTBPATH=${PROJECT_SOURCE_DIR}
)
