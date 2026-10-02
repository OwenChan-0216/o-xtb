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
  "landscape-scan"
  "landscape-vib"
  "landscape-saddle"
  "landscape-path"
  "landscape-irc"
  "landscape-e2e"
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
# the rundir is rebuilt, because the check below asserts the *absence* of the
# unprefixed output names (a leftover file of an earlier run would satisfy the
# existence checks otherwise)
file(REMOVE_RECURSE "${RUNDIR}")
file(MAKE_DIRECTORY "${RUNDIR}")
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
foreach(name "landscape1.xtbopt.xyz" "landscape1.xtb.trj")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
# the namespace has to replace the default name, not to supplement it
foreach(name "xtbopt.xyz" "xtb.trj")
  if(EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "--namespace landscape1 also wrote the unprefixed ${name}")
  endif()
endforeach()
]=])
add_test("xtb/landscape-opt"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${LANDSCAPE-RUNDIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_check.cmake")

# Landscape suite: the file namespace of the `--lopt` geometry and trajectory
# (defect N-1 of the final fix round).
#
# The optimised geometry and the trajectory are written by
# `xtb_landscape_log::landscape_write_files`, which used the bare names
# `xtbopt.xyz` / `xtb.trj` while every other landscape writer (and the
# pre-existing `--opt`, whose geometry goes through `open_file`) passes its name
# through `get_namespace`.  Two `--lopt` runs with different namespaces in one
# directory therefore overwrote each other's geometry file, which is exactly
# what the namespace exists to prevent.
#
# The check pins both sides of the contract:
#  1. without `--namespace` the names stay `xtbopt.xyz` / `xtb.trj`
#     (tool-chain compatibility), and
#  2. two runs in the *same* directory with `--namespace c1` / `--namespace c2`
#     write `c1.xtbopt.xyz` / `c2.xtbopt.xyz` (and the matching `.trj` files),
#     the first geometry survives the second run byte for byte, the two
#     geometries differ, and no unprefixed `xtbopt.xyz` appears.
#
# The two runs use the two convergence levels so that the geometries are
# genuinely different: comparing the same input twice could not tell an exact
# overwrite from a correct pair of identical files.
set(LANDSCAPE-H2O-STRETCH "${CMAKE_CURRENT_BINARY_DIR}/landscape_h2o_stretch.xyz")
file(WRITE "${LANDSCAPE-H2O-STRETCH}"
  "3\nstretched water\nO  0.0000000  0.0000000  0.0000000\n"
  "H  0.0000000  0.0000000  1.3000000\n"
  "H  1.3000000  0.0000000 -0.4000000\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_opt_namespace.cmake" [=[
# the rundir is rebuilt: the check asserts the *absence* of `xtbopt.xyz`
file(REMOVE_RECURSE "${RUNDIR}")
file(MAKE_DIRECTORY "${RUNDIR}/plain" "${RUNDIR}/two")
# 1. the default names
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lopt --lopt-level loose --norestart
  WORKING_DIRECTORY "${RUNDIR}/plain"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the default --lopt run failed with status ${status}\n${output}")
endif()
foreach(name "xtbopt.xyz" "xtb.trj")
  if(NOT EXISTS "${RUNDIR}/plain/${name}")
    message(FATAL_ERROR "without --namespace the output is still ${name}, but ${name} was not written\n${output}")
  endif()
  file(SIZE "${RUNDIR}/plain/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
# 2. two namespaces in one directory
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lopt --lopt-level loose --norestart
          --namespace c1
  WORKING_DIRECTORY "${RUNDIR}/two"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the --namespace c1 run failed with status ${status}\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/two/c1.xtbopt.xyz")
  message(FATAL_ERROR "--namespace c1 wrote no c1.xtbopt.xyz\n${output}")
endif()
file(MD5 "${RUNDIR}/two/c1.xtbopt.xyz" c1_before)
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lopt --lopt-level vtight --norestart
          --namespace c2
  WORKING_DIRECTORY "${RUNDIR}/two"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the --namespace c2 run failed with status ${status}\n${output}")
endif()
foreach(name "c1.xtbopt.xyz" "c2.xtbopt.xyz" "c1.xtb.trj" "c2.xtb.trj")
  if(NOT EXISTS "${RUNDIR}/two/${name}")
    message(FATAL_ERROR "${name} was not written\n${output}")
  endif()
endforeach()
if(EXISTS "${RUNDIR}/two/xtbopt.xyz")
  message(FATAL_ERROR "a namespaced run also wrote the unprefixed xtbopt.xyz")
endif()
file(MD5 "${RUNDIR}/two/c1.xtbopt.xyz" c1_after)
if(NOT c1_before STREQUAL c1_after)
  message(FATAL_ERROR "the --namespace c2 run overwrote c1.xtbopt.xyz")
endif()
file(READ "${RUNDIR}/two/c1.xtbopt.xyz" c1_text)
file(READ "${RUNDIR}/two/c2.xtbopt.xyz" c2_text)
if(c1_text STREQUAL c2_text)
  message(FATAL_ERROR "the two namespaces hold the same geometry; the check cannot tell an overwrite from a correct pair")
endif()
]=])
add_test("xtb/landscape-opt-namespace"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O-STRETCH}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-opt-namespace
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_opt_namespace.cmake")

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

# Landscape suite: the `--lopt-hessian` flag must select the Hessian backend.
#
# `model` is the cheap Lindh-D2 model Hessian and seeds the quasi-Newton
# approximation of BFGS and the trust region step of RFO; the CLI value must
# reach the engine (visible in the `Hessian source:` header), every combination
# must converge on water and the converged energies must agree to the printed
# precision (the first three decimals of the hartree value).
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_hessian.cmake" [=[
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
  if(NOT output MATCHES "landscape: converged")
    message(FATAL_ERROR "xtb --lopt ${args} did not converge\n${output}")
  endif()
  file(READ "${RUNDIR}/xtbopt.xyz" xyzfile)
  string(REGEX MATCH "energy: +(-?[0-9]+[.][0-9]+)" _ "${xyzfile}")
  if(NOT CMAKE_MATCH_1)
    message(FATAL_ERROR "the ${suffix} run reported no energy\n${xyzfile}")
  endif()
  string(SUBSTRING "${CMAKE_MATCH_1}" 0 6 energy_prefix)
  set(${suffix}_prefix "${energy_prefix}" PARENT_SCOPE)
  string(REGEX MATCH "Hessian source: +([a-z]+)" _ "${output}")
  set(${suffix}_source "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()
run_case("--lopt-engine lbfgs --lopt-hessian model" model_lbfgs)
run_case("--lopt-engine lbfgs --lopt-hessian numerical" num_lbfgs)
run_case("--lopt-engine rfo --lopt-hessian model" model_rfo)
run_case("--lopt-engine rfo --lopt-hessian numerical" num_rfo)
if(NOT model_lbfgs_source STREQUAL "model")
  message(FATAL_ERROR
    "--lopt-hessian model did not reach the engine (${model_lbfgs_source})")
endif()
if(NOT model_rfo_source STREQUAL "model")
  message(FATAL_ERROR
    "--lopt-hessian model did not reach the RFO engine (${model_rfo_source})")
endif()
if(NOT num_lbfgs_source STREQUAL "numerical")
  message(FATAL_ERROR
    "the default Hessian source is not numerical (${num_lbfgs_source})")
endif()
if(NOT num_rfo_source STREQUAL "numerical")
  message(FATAL_ERROR
    "--lopt-hessian numerical is not reported for rfo (${num_rfo_source})")
endif()
if(NOT model_lbfgs_prefix STREQUAL num_lbfgs_prefix)
  message(FATAL_ERROR
    "lbfgs converges differently for model (${model_lbfgs_prefix}) and numerical (${num_lbfgs_prefix})")
endif()
if(NOT model_rfo_prefix STREQUAL num_rfo_prefix)
  message(FATAL_ERROR
    "rfo converges differently for model (${model_rfo_prefix}) and numerical (${num_rfo_prefix})")
endif()
]=])
add_test("xtb/landscape-opt-hessian"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-hessian
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_hessian.cmake")

# Landscape suite: the `--lopt-hessian` error branch.
add_test("xtb/landscape-hessian-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lopt --lopt-hessian bogus"
  "-DPATTERN=Unknown landscape Hessian source"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

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

# Landscape suite: CLI level smoke test of the `--lscan` run type.
#
# The scan must terminate with status 0, write `xtbscan.log` with one frame
# per scan point (a bidirectional scan of three steps has 2*3+1 points) and
# report the constraint residual and the hysteresis in its output.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scan.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lscan --lscan-coord angle
          --lscan-atoms 2,1,3 --lscan-step 3 --lscan-nstep 3
          --lscan-level loose --norestart --namespace landscape2
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lscan terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: relaxed scan")
  message(FATAL_ERROR "the scan header was not printed\n${output}")
endif()
if(NOT output MATCHES "hysteresis: max")
  message(FATAL_ERROR "no hysteresis report was printed\n${output}")
endif()
if(NOT output MATCHES "landscape task terminated: scan completed")
  message(FATAL_ERROR "the scan did not complete\n${output}")
endif()
# "scan completed" is a prefix of "scan completed with unconverged points", so
# the status check above cannot tell the two apart on its own
# (docs/_landscape-recon/17-m2-independent-review.md section 3.1).
if(output MATCHES "scan completed with unconverged points")
  message(FATAL_ERROR "a scan point did not converge\n${output}")
endif()
# the scan log honours the namespace, exactly like the existing `--scan`
if(NOT EXISTS "${RUNDIR}/landscape2.xtbscan.log")
  message(FATAL_ERROR "landscape2.xtbscan.log was not written")
endif()
file(SIZE "${RUNDIR}/landscape2.xtbscan.log" size)
if(size EQUAL 0)
  message(FATAL_ERROR "landscape2.xtbscan.log is empty")
endif()
# one frame is two header lines plus three atoms
file(READ "${RUNDIR}/landscape2.xtbscan.log" scanlog)
string(REGEX MATCHALL "energy:" frames "${scanlog}")
list(LENGTH frames nframes)
if(NOT nframes EQUAL 7)
  message(FATAL_ERROR "xtbscan.log holds ${nframes} frames, expected 7")
endif()
]=])
add_test("xtb/landscape-scan-cli"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-scan
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scan.cmake")

# Landscape suite: a scan point whose single point fails must not be
# written as a fabricated energy.
# The rigid geometry of the second point of a 5 angstrom distance scan sits at
# 5.96 angstrom, where the SCC does not converge.  The run has to terminate
# with a readable diagnostic and a non-zero status, and the scan log may
# neither contain a frame with `energy: 0.000000000000` nor one frame per
# requested point (a point without an energy is omitted).
#
# `test/unit/landscape_cli_check.py` implements exactly the same conditions
# for the meson build (test `landscape scan failed point`).
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scan_fail.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lscan --lscan-mode rigid
          --lscan-coord distance --lscan-atoms 1,2 --lscan-step 5.0
          --lscan-nstep 2 --namespace landscape3
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(status EQUAL 0)
  message(FATAL_ERROR "the failed scan points did not fail the run\n${output}")
endif()
if(NOT output MATCHES "scan points failed")
  message(FATAL_ERROR "the failed scan points were not reported\n${output}")
endif()
file(READ "${RUNDIR}/landscape3.xtbscan.log" scanlog)
if(scanlog MATCHES "energy: 0.000000000000")
  message(FATAL_ERROR "a failed scan point was written with a zero energy\n${scanlog}")
endif()
string(REGEX MATCHALL "energy:" frames "${scanlog}")
list(LENGTH frames nframes)
if(NOT nframes LESS 5)
  message(FATAL_ERROR "the scan log holds ${nframes} frames, expected fewer than 5")
endif()
]=])
add_test("xtb/landscape-scan-failed-point"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-scan-fail
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scan_fail.cmake")

# Landscape suite: `--lscan` error branches.
add_test("xtb/landscape-scan-coord-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lscan --lscan-coord bogus"
  "-DPATTERN=Unknown landscape scan coordinate"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-scan-nstep-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lscan --lscan-coord distance --lscan-atoms 1,2 --lscan-step 0.1 --lscan-nstep 0"
  "-DPATTERN=at least one step is required"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-scan-atom-range"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lscan --lscan-coord distance --lscan-atoms 1,9 --lscan-step 0.1 --lscan-nstep 2"
  "-DPATTERN=outside 1..3"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# Landscape suite: CLI level check of the `--lvib` run type (M3).
#
# The task must write the four output files of the existing `--hess` run, must
# report the energy of the analysed geometry (the `res` write-back; without it
# the TOTAL ENERGY line would show an unrelated energy), and the `hessian` file
# it writes must be readable by the file provider: the re-run from the file has
# to reproduce the frequencies of the direct numerical Hessian.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_vib.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lvib --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lvib terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: harmonic frequencies")
  message(FATAL_ERROR "the frequency header was not printed\n${output}")
endif()
if(NOT output MATCHES "Hessian source: +numerical")
  message(FATAL_ERROR "the Hessian source was not reported\n${output}")
endif()
if(NOT output MATCHES "landscape task terminated: frequency analysis completed")
  message(FATAL_ERROR "the frequency task did not complete\n${output}")
endif()
if(NOT output MATCHES "modes: 3 internal, 6 projected zero modes")
  message(FATAL_ERROR "the mode count of water is wrong\n${output}")
endif()
if(NOT output MATCHES "linear molecule: +F")
  message(FATAL_ERROR "water was classified as linear\n${output}")
endif()
# The direct run builds the numerical Hessian from 6N displaced single points
# plus the gradient of the input geometry: 1 + 6*3 = 19 evaluations for water.
# The counter is asserted, not just printed, because the `--lvib-hessian file`
# check below claims that the file provider *saves* those evaluations
# (finding P2-7 of `52-m7-review-round2.md`).
if(NOT output MATCHES "landscape engine: energy evaluations +([0-9]+)")
  message(FATAL_ERROR "the direct run reports no evaluation counter\n${output}")
endif()
set(direct_eval "${CMAKE_MATCH_1}")
if(NOT direct_eval EQUAL 19)
  message(FATAL_ERROR "the direct --lvib run used ${direct_eval} evaluations, expected 1+6N = 19\n${output}")
endif()
foreach(name "hessian" "vibspectrum" "vib_normal_modes" "g98.out")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
# the reported task energy must be the energy of the TOTAL ENERGY line
string(REGEX MATCH "energy: +(-?[0-9]+[.][0-9]+)" _ "${output}")
set(task_energy "${CMAKE_MATCH_1}")
string(REGEX MATCH "TOTAL ENERGY +(-?[0-9]+[.][0-9]+)" _ "${output}")
set(total_energy "${CMAKE_MATCH_1}")
if(NOT task_energy)
  message(FATAL_ERROR "the frequency task reported no energy\n${output}")
endif()
if(NOT task_energy STREQUAL total_energy)
  message(FATAL_ERROR
    "the task energy (${task_energy}) is not the reported TOTAL ENERGY (${total_energy})")
endif()
string(REGEX MATCH "eigval : +([-0-9. ]+)" _ "${output}")
string(REGEX REPLACE " +" " " vib_freqs "${CMAKE_MATCH_1}")
# the file provider must reproduce the direct numerical Hessian
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lvib --lvib-hessian file
          --lvib-hessian-file hessian --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE file_output
  ERROR_VARIABLE file_output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "reading the Hessian file failed with status ${status}\n${file_output}")
endif()
if(NOT file_output MATCHES "Hessian file: +hessian")
  message(FATAL_ERROR "the file provider did not report its file\n${file_output}")
endif()
# ... and it must *save* the displaced single points: reading the file needs the
# gradient of the input geometry only, so the same task drops from 19 to 1
# evaluation.  Without this assertion a provider that silently recomputed the
# Hessian would stay green (finding P2-7 of `52-m7-review-round2.md`).
if(NOT file_output MATCHES "landscape engine: energy evaluations +([0-9]+)")
  message(FATAL_ERROR "the file run reports no evaluation counter\n${file_output}")
endif()
set(file_eval "${CMAKE_MATCH_1}")
if(NOT file_eval EQUAL 1)
  message(FATAL_ERROR "--lvib-hessian file used ${file_eval} evaluations, expected 1; the provider did not reuse the file\n${file_output}")
endif()
if(NOT direct_eval GREATER file_eval)
  message(FATAL_ERROR "the Hessian file did not save evaluations (${direct_eval} vs ${file_eval})")
endif()
string(REGEX MATCH "eigval : +([-0-9. ]+)" _ "${file_output}")
string(REGEX REPLACE " +" " " file_freqs "${CMAKE_MATCH_1}")
if(NOT file_freqs STREQUAL vib_freqs)
  message(FATAL_ERROR
    "the Hessian file reproduces different frequencies (${file_freqs} vs ${vib_freqs})")
endif()
]=])
add_test("xtb/landscape-vib-cli"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-vib
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_vib.cmake")

# Landscape suite: the CLI `--etemp` reaches the landscape engine (guard of the
# `main.F90` sync, `landscape_engine_control%etemp <- set%etemp`).
#
# The engine control is the single source of truth for the electronic
# temperature (`push_calculator_etemp` overwrites the calculator field with it),
# so a missing sync would silently run every landscape task at the 300 K
# default.  The stretched H2 is the near-degenerate case of report 21 section
# 3.1, whose only mode shifts by >30 % between 300 K and 5000 K: the two runs
# must therefore report different effective temperatures and different
# frequencies.  Deleting the sync line in `main.F90` turns this test red (both
# runs print 300 K and give identical `eigval`).
# The input is generated in the build directory (the repository stays free of
# test data).
set(LANDSCAPE-H2 "${CMAKE_CURRENT_BINARY_DIR}/landscape_h2.xyz")
file(WRITE "${LANDSCAPE-H2}"
  "2\nstretched H2 (2.4 A)\nH  0.0000000  0.0000000 -2.2674600\n"
  "H  0.0000000  0.0000000  2.2674600\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_vib_etemp.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lvib --norestart --etemp 300
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE cold
  ERROR_VARIABLE cold
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lvib --etemp 300 terminated with status ${status}\n${cold}")
endif()
if(NOT cold MATCHES "landscape engine: etemp +300[.]000 K")
  message(FATAL_ERROR "the effective electronic temperature 300 K was not reported\n${cold}")
endif()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lvib --norestart --etemp 5000
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE hot
  ERROR_VARIABLE hot
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lvib --etemp 5000 terminated with status ${status}\n${hot}")
endif()
if(NOT hot MATCHES "landscape engine: etemp +5000[.]000 K")
  message(FATAL_ERROR
    "--etemp 5000 did not reach the engine control (missing CLI sync)\n${hot}")
endif()
string(REGEX MATCH "eigval : +([-0-9. ]+)" _ "${cold}")
set(cold_freqs "${CMAKE_MATCH_1}")
string(REGEX MATCH "eigval : +([-0-9. ]+)" _ "${hot}")
set(hot_freqs "${CMAKE_MATCH_1}")
if(NOT cold_freqs)
  message(FATAL_ERROR "the 300 K run reported no frequencies\n${cold}")
endif()
if(NOT hot_freqs)
  message(FATAL_ERROR "the 5000 K run reported no frequencies\n${hot}")
endif()
if(cold_freqs STREQUAL hot_freqs)
  message(FATAL_ERROR
    "the electronic temperature did not change the frequencies (${cold_freqs})")
endif()
]=])
add_test("xtb/landscape-vib-etemp"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-vib-etemp
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_vib_etemp.cmake")

# Landscape suite: the `hessian` file of `--lvib` carries the namespace once.
#
# `get_namespace` is not idempotent, so the task must not prefix the name
# itself on top of the writer: with `--namespace ns` the file has to be
# `ns.hessian` (the name `--hess` produces as well) and the re-run with
# `--lvib-hessian file --lvib-hessian-file hessian --namespace ns` has to find
# and reproduce it.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_vib_namespace.cmake" [=[
# rebuilt: the check asserts the *absence* of the unprefixed output names
file(REMOVE_RECURSE "${RUNDIR}")
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lvib --norestart --namespace ns
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lvib --namespace ns terminated with status ${status}\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/ns.hessian")
  message(FATAL_ERROR "the namespaced hessian file was not written\n${output}")
endif()
if(EXISTS "${RUNDIR}/ns.ns.hessian")
  message(FATAL_ERROR "the hessian file name carries the namespace twice")
endif()
# every other file of the task goes through the namespace as well, and the
# unprefixed name must not appear next to it (finding N-2 of the final fix
# round: `vibspectrum`, `vib_normal_modes` and `g98.out` were namespaced in
# fact - through `open_file`, this suite's writer and `g98fake2` - but no test
# pinned it)
foreach(name "hessian" "vibspectrum" "vib_normal_modes" "g98.out")
  if(NOT EXISTS "${RUNDIR}/ns.${name}")
    message(FATAL_ERROR "--namespace ns wrote no ns.${name}\n${output}")
  endif()
  if(EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "--namespace ns also wrote the unprefixed ${name}")
  endif()
endforeach()
string(REGEX MATCH "eigval : +([-0-9. ]+)" _ "${output}")
string(REGEX REPLACE " +" " " vib_freqs "${CMAKE_MATCH_1}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lvib --lvib-hessian file
          --lvib-hessian-file hessian --norestart --namespace ns
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE file_output
  ERROR_VARIABLE file_output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "reading the namespaced Hessian file failed with status ${status}\n${file_output}")
endif()
string(REGEX MATCH "eigval : +([-0-9. ]+)" _ "${file_output}")
string(REGEX REPLACE " +" " " file_freqs "${CMAKE_MATCH_1}")
if(NOT file_freqs STREQUAL vib_freqs)
  message(FATAL_ERROR
    "the namespaced Hessian file reproduces different frequencies (${file_freqs} vs ${vib_freqs})")
endif()
]=])
add_test("xtb/landscape-vib-namespace"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-vib-namespace
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_vib_namespace.cmake")

# Landscape suite: the error branches of the frequency task and of the scan
# Hessian selector.
add_test("xtb/landscape-vib-odlr"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lvib --lvib-odlr"
  "-DPATTERN=ODLR approximation"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-vib-hessian-missing-file"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lvib --lvib-hessian file --lvib-hessian-file no_such_file.dat"
  "-DPATTERN=cannot open Hessian file"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-vib-hessian-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lvib --lvib-hessian bogus"
  "-DPATTERN=Unknown landscape Hessian source"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# Landscape suite: unusable thermochemical parameters must be rejected instead
# of printing Inf/NaN (a zero temperature divides by zero in the RRHO model)
# or of silently inverting the meaning of a flag (a positive imaginary cutoff).
add_test("xtb/landscape-vib-temperature-invalid"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lvib --lvib-temp 0"
  "-DPATTERN=the thermochemical temperature must be positive"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-vib-imag-cutoff-invalid"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lvib --lvib-imag-cutoff 20"
  "-DPATTERN=the imaginary frequency cutoff must not be positive"
  -DRUNDIR=${LANDSCAPE-ERROR-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# Landscape suite: `--lscan-max-steps` reaches the inner relaxation, and a scan
# in which no point converges reports a missing minimum instead of a number
# (M2 leftover M-1/M-2).
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_maxsteps.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lscan --lscan-coord angle
          --lscan-atoms 2,1,3 --lscan-step 3 --lscan-nstep 2
          --lscan-max-steps 0 --norestart --namespace landscape4
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
# M7 (PLAN section 12.11 INFO-3): a scan without a single converged point has
# no usable result, so the process has to exit non-zero.  The NaN energy is
# visible in the scan table (`lowest energy: +NaN`) and *replaces* the trailing
# TOTAL ENERGY block: `env%error` terminates the process in `env%checkpoint`
# before that block is printed (finding I-6 of `50-m7-independent-review.md`).
# Before this round the branch only warned and the run exited 0 (INFO-3 of
# PLAN section 12.11), which a caller of a scan chain cannot distinguish from
# a valid result.
if(status EQUAL 0)
  message(FATAL_ERROR "a scan without a converged point exited 0\n${output}")
endif()
if(NOT output MATCHES "scan completed without a converged point")
  message(FATAL_ERROR "the missing convergence was not reported\n${output}")
endif()
if(NOT output MATCHES "lowest energy: +NaN")
  message(FATAL_ERROR "the unconverged scan reported a minimum\n${output}")
endif()
# the points were evaluated, so their frames carry energies; the scan is
# bidirectional, so a two step sweep has 2*2+1 = 5 points
file(READ "${RUNDIR}/landscape4.xtbscan.log" scanlog)
string(REGEX MATCHALL "energy:" frames "${scanlog}")
list(LENGTH frames nframes)
if(NOT nframes EQUAL 5)
  message(FATAL_ERROR "xtbscan.log holds ${nframes} frames, expected 5")
endif()
# with a real step budget the same scan converges again
file(REMOVE "${RUNDIR}/landscape4.xtbscan.log")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lscan --lscan-coord angle
          --lscan-atoms 2,1,3 --lscan-step 3 --lscan-nstep 2
          --lscan-max-steps 256 --lscan-level loose --norestart
          --namespace landscape4
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the reference scan failed with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape task terminated: scan completed[\n]")
  if(NOT output MATCHES "landscape task terminated: scan completed")
    message(FATAL_ERROR "the reference scan did not complete\n${output}")
  endif()
endif()
if(output MATCHES "without a converged point")
  message(FATAL_ERROR "the reference scan reported a missing minimum\n${output}")
endif()
]=])
add_test("xtb/landscape-scan-max-steps"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-maxsteps
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_maxsteps.cmake")

# Landscape suite: the `--lscan-hessian` selector reaches the scan engine.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scanhess.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lscan --lscan-method rfo
          --lscan-hessian model --lscan-coord angle --lscan-atoms 2,1,3
          --lscan-step 3 --lscan-nstep 1 --lscan-level loose --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lscan --lscan-hessian model failed with status ${status}\n${output}")
endif()
if(NOT output MATCHES "Hessian source: +model")
  message(FATAL_ERROR "the scan Hessian source was not reported\n${output}")
endif()
]=])
add_test("xtb/landscape-scan-hessian"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-scanhess
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_scanhess.cmake")

# Landscape suite: end-to-end smoke test of the `--lts` run type.
#
# The input is a bent HCN, a guess for the HCN/HNC transition state (the linear
# equilibrium geometry is already a minimum and would converge immediately with
# zero imaginary modes).  The search must converge to a stationary point with
# exactly one imaginary mode and write `xtbts.xyz` and `xtbts.log`.
set(LANDSCAPE-HCN "${CMAKE_CURRENT_BINARY_DIR}/landscape_hcn.xyz")
file(WRITE "${LANDSCAPE-HCN}"
  "3\nbent HCN (transition state guess)\n"
  "H  0.0000000  1.0500000  0.0000000\n"
  "C  0.0000000  0.0000000  0.0000000\n"
  "N  1.1560000  0.0000000  0.0000000\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "xtbts.xyz" "xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method prfo --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "the transition state search did not converge\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the located point is not a first order saddle point\n${output}")
endif()
# H4 of `29-m4-independent-review.md`: on a clean molecule the rigid body round
# off must not be counted as negative curvature, so the `hlow` lift stays off.
if(output MATCHES "lifted=T")
  message(FATAL_ERROR "the curvature lift engaged on a clean run\n${output}")
endif()
# M5: the final transition vector is reported at the converged geometry
if(NOT output MATCHES "final transition vector")
  message(FATAL_ERROR "the final transition vector was not reported\n${output}")
endif()
if(NOT output MATCHES "landscape engine: etemp +300[.]000 K")
  message(FATAL_ERROR "the frozen electronic temperature was not reported\n${output}")
endif()
foreach(name "xtbts.xyz" "xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
file(READ "${RUNDIR}/xtbts.log" log)
if(NOT log MATCHES "confirmation imaginary modes: 1")
  message(FATAL_ERROR "the log does not report the imaginary mode count\n${log}")
endif()
# the restricted step branch must reach the same kind of stationary point
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method bprfo --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method bprfo terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "the B-PRFO search did not converge\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the B-PRFO point is not a first order saddle point\n${output}")
endif()
]=])
add_test("xtb/landscape-ts-prfo"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-ts
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts.cmake")

# Landscape suite: the CLI `--etemp` reaches the transition state engine (the
# `main.F90` sync guard of M4 hard constraint 1).  A missing sync would leave
# the settings at 300 K, so the printed frozen and effective temperatures are
# checked against the requested 5000 K.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_etemp.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method prfo --etemp 5000
          --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --etemp 5000 terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "electronic temperature: +5000[.]000 K")
  message(FATAL_ERROR "the frozen electronic temperature is not 5000 K\n${output}")
endif()
if(NOT output MATCHES "landscape engine: etemp +5000[.]000 K")
  message(FATAL_ERROR "--etemp 5000 did not reach the engine control\n${output}")
endif()
# MEDIUM-3 of `31-m4-review-round2.md`: the *result* field has to carry the
# effective value as well.  `landscape_result%write_log` prints it as
# `etemp:`, which is a different line from the two settings/engine echoes above,
# so deleting `result%etemp = engine%effective_etemp()` in the task turns this
# test red (the line disappears).
if(NOT output MATCHES "etemp: +5000[.]000 K")
  message(FATAL_ERROR "the result object does not carry the effective etemp\n${output}")
endif()
file(READ "${RUNDIR}/xtbts.log" log)
if(NOT log MATCHES "electronic temperature [(]frozen[)]: +5000[.]000 K")
  message(FATAL_ERROR "xtbts.log does not carry the effective etemp\n${log}")
endif()
]=])
add_test("xtb/landscape-ts-etemp"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-ts-etemp
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_etemp.cmake")

# Landscape suite: the dimer search locates the same transition state without
# ever building a Hessian.  It is started from the deterministic `force`
# initial axis (the largest gradient component direction, PLAN section 6.3);
# the run has to converge to a first order saddle point, write the two files
# and print its rotation/torque diagnostics and the frozen temperature.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_dimer.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "xtbts.xyz" "xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method dimer
          --lts-ninit force --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method dimer terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "dimer initial axis: force")
  message(FATAL_ERROR "the deterministic initial axis was not used\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "the dimer search did not converge\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the dimer point is not a first order saddle point\n${output}")
endif()
if(NOT output MATCHES "landscape engine: etemp +300[.]000 K")
  message(FATAL_ERROR "the frozen electronic temperature was not reported\n${output}")
endif()
# the rotation and translation diagnostics of the dimer
if(NOT output MATCHES "dimer rotation: iterations [0-9]+, torque rms")
  message(FATAL_ERROR "the rotation/torque diagnostic is missing\n${output}")
endif()
if(NOT output MATCHES "dimer curvature:")
  message(FATAL_ERROR "the curvature diagnostic is missing\n${output}")
endif()
foreach(name "xtbts.xyz" "xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
file(READ "${RUNDIR}/xtbts.log" log)
if(NOT log MATCHES "confirmation imaginary modes: 1")
  message(FATAL_ERROR "the log does not report the imaginary mode count\n${log}")
endif()
if(NOT log MATCHES "dimer")
  message(FATAL_ERROR "the log does not identify the dimer method")
endif()
]=])
add_test("xtb/landscape-ts-dimer"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-ts-dimer
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_dimer.cmake")

# Landscape suite: the dimer-only CLI options reach the settings (the unit
# tests cover their effect); a missing or unknown value must abort with the
# documented message.
add_test("xtb/landscape-ts-dimer-ninit-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-method dimer --lts-ninit bogus"
  "-DPATTERN=Unknown landscape dimer initial axis"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-ts-dimer-delta-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-method dimer --lts-delta"
  "-DPATTERN=The --lts-delta flag requires a number"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-ts-dimer-seed-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-method dimer --lts-seed"
  "-DPATTERN=The --lts-seed flag requires an integer"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-ts-method-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-method bogus"
  "-DPATTERN=Unknown landscape transition state method"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# Landscape suite: H2 of the independent review.  A search that converges to a
# *minimum* (0 imaginary modes) is not a transition state; it must abort with a
# non-zero exit status and a readable diagnosis while still writing the
# geometry and the log for debugging.  The input is a linear HNC, whose own
# minimum traps the P-RFO search when the escape from a minimum is disabled
# (`--lts-escape-step 0`, which is what this test pins: `xtb/landscape-ts-escape`
# is the same input with the default escape, where the walk out of the minimum
# turns the search into a successful one).
set(LANDSCAPE-HNC "${CMAKE_CURRENT_BINARY_DIR}/landscape_hnc.xyz")
file(WRITE "${LANDSCAPE-HNC}"
  "3\nlinear HNC (a minimum)\n"
  "N  0.0000000  1.1560000  0.0000000\n"
  "C  0.0000000  0.0000000  0.0000000\n"
  "H  0.0000000 -1.0500000  0.0000000\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_minimum.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "xtbts.xyz" "xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method prfo --norestart
          --lts-escape-step 0
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(status EQUAL 0)
  message(FATAL_ERROR "a minimum was accepted as a transition state\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 0")
  message(FATAL_ERROR "the imaginary mode count is not reported\n${output}")
endif()
if(NOT output MATCHES "confirmation: minimum")
  message(FATAL_ERROR "the minimum was not named as such\n${output}")
endif()
if(NOT output MATCHES "not a first order saddle point")
  message(FATAL_ERROR "the failure was not reported\n${output}")
endif()
foreach(name "xtbts.xyz" "xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written despite the failure")
  endif()
endforeach()
]=])
add_test("xtb/landscape-ts-minimum"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HNC}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-ts-minimum
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_minimum.cmake")

# Landscape suite: MEDIUM-1 of `31-m4-review-round2.md`.  From a *minimum* the
# P-RFO/B-PRFO model step descends, so following the lowest internal mode does
# not climb; the driver walks the geometry along that mode until its curvature
# turns negative and then starts the search.  The same linear HNC input as
# `xtb/landscape-ts-minimum` therefore reaches the HCN/HNC saddle point here
# (1 imaginary mode, exit 0) instead of falling back to the minimum.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_escape.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "xtbts.xyz" "xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method prfo --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the escaped search terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "escape from a minimum: +[0-9]+ push")
  message(FATAL_ERROR "the escape walk out of the minimum was not reported\n${output}")
endif()
if(NOT output MATCHES "escape from a minimum: +0[.]200000 bohr")
  message(FATAL_ERROR "the configured escape displacement was not reported\n${output}")
endif()
if(NOT output MATCHES "selected mode, rigid body overlap: +0[.]000000")
  message(FATAL_ERROR "a rigid body direction was followed\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the escaped search did not reach a first order saddle\n${output}")
endif()
if(NOT output MATCHES "confirmation: first order saddle point")
  message(FATAL_ERROR "the saddle confirmation is missing\n${output}")
endif()
foreach(name "xtbts.xyz" "xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
endforeach()
file(READ "${RUNDIR}/xtbts.log" log)
if(NOT log MATCHES "confirmation imaginary modes: 1")
  message(FATAL_ERROR "the log does not report the imaginary mode count\n${log}")
endif()
# the restricted step branch of the same escape has to reach the same saddle
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method bprfo --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the escaped B-PRFO search terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "escape from a minimum: +[0-9]+ push")
  message(FATAL_ERROR "the B-PRFO escape walk was not reported\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the escaped B-PRFO search did not reach a saddle\n${output}")
endif()
]=])
add_test("xtb/landscape-ts-escape"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HNC}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-ts-escape
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_escape.cmake")

# Landscape suite: the `--lts` output files honour `--namespace` (M3 of the
# review), exactly like `--lscan` and `--lvib`: `--namespace landscape6 --lts`
# must write `landscape6.xtbts.xyz`/`landscape6.xtbts.log` with a single
# prefix.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_namespace.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "landscape6.xtbts.xyz" "landscape6.xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method prfo --norestart
          --namespace landscape6
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --namespace terminated with status ${status}\n${output}")
endif()
foreach(name "landscape6.xtbts.xyz" "landscape6.xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written (namespace not applied)")
  endif()
endforeach()
]=])
add_test("xtb/landscape-ts-namespace"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-ts-namespace
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ts_namespace.cmake")

# Landscape suite: H1 of the review.  `--lts-step`, `--lts-sccacc` and
# `--lts-step0` are the client side of the finite difference tightening and of
# the dimer first translation; a missing value has to abort with the documented
# message instead of silently keeping the default.
add_test("xtb/landscape-ts-step-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-step"
  "-DPATTERN=The --lts-step flag requires a number"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-ts-sccacc-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-sccacc"
  "-DPATTERN=The --lts-sccacc flag requires a number"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-ts-step0-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-method dimer --lts-step0"
  "-DPATTERN=The --lts-step0 flag requires a number"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-ts-escape-step-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lts --lts-escape-step"
  "-DPATTERN=The --lts-escape-step flag requires a number"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# ---------------------------------------------------------------------------
# Landscape suite: intrinsic reaction coordinate (`--lirc`, M6).
#
# The input is the **converged** transition state of the bent HCN guess: the
# script first runs `--lts` (the guess itself is only near the saddle, and an
# IRC from a non-stationary geometry funnels both directions into the same
# basin, measured in report 42).  The IRC has to confirm exactly one imaginary
# mode, print the frozen etemp and the phase component that defines forward,
# terminate both directions at a minimum, write the four output files with a
# single namespace prefix and be **bitwise reproducible** (the phase convention
# fixes forward deterministically).
# ---------------------------------------------------------------------------
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
# step 1: converge the transition state of the bent HCN guess
foreach(name "irc0.xtbts.xyz" "irc0.xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method prfo --norestart
          --namespace irc0
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the preparation --lts run failed with status ${status}\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/irc0.xtbts.xyz")
  message(FATAL_ERROR "the preparation --lts run wrote no xtbts.xyz\n${output}")
endif()
# step 2: the IRC from the converged transition state
foreach(name "irc1.irc_forward.xyz" "irc1.irc_backward.xyz" "irc1.irc_path.xyz" "irc1.irc.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/irc0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
          --norestart --namespace irc1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lirc terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: intrinsic reaction coordinate [(]gs[)]")
  message(FATAL_ERROR "the IRC header was not printed\n${output}")
endif()
if(NOT output MATCHES "transition state imaginary modes: +1")
  message(FATAL_ERROR "the transition state was not confirmed\n${output}")
endif()
if(NOT output MATCHES "phase component: +([0-9.]+)")
  message(FATAL_ERROR "the phase component of the forward direction was not reported\n${output}")
endif()
set(PHASE "${CMAKE_MATCH_1}")
if(PHASE STREQUAL "0.000000")
  message(FATAL_ERROR "the phase component is zero\n${output}")
endif()
if(NOT output MATCHES "landscape engine: etemp +300[.]000 K")
  message(FATAL_ERROR "the frozen electronic temperature was not reported\n${output}")
endif()
if(output MATCHES "termination forward: +error")
  message(FATAL_ERROR "the forward direction terminated with an error\n${output}")
endif()
if(output MATCHES "termination backward: +error")
  message(FATAL_ERROR "the backward direction terminated with an error\n${output}")
endif()
if(NOT output MATCHES "forward reached minimum: +T")
  message(FATAL_ERROR "the forward endpoint is not assigned to a minimum\n${output}")
endif()
if(NOT output MATCHES "backward reached minimum: +T")
  message(FATAL_ERROR "the backward endpoint is not assigned to a minimum\n${output}")
endif()
foreach(name "irc1.irc_forward.xyz" "irc1.irc_backward.xyz" "irc1.irc_path.xyz" "irc1.irc.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
# the merged path marks the highest point as the transition state and holds
# one frame per point of both directions plus the transition state
file(READ "${RUNDIR}/irc1.irc_path.xyz" pathfile)
if(NOT pathfile MATCHES " TS")
  message(FATAL_ERROR "the transition state is not marked in irc_path.xyz")
endif()
string(REGEX MATCHALL "frame " frames "${pathfile}")
list(LENGTH frames nframes)
if(nframes LESS 5)
  message(FATAL_ERROR "irc_path.xyz holds only ${nframes} frames")
endif()
# the two directions reach **different** minima (HCN and HNC)
file(READ "${RUNDIR}/irc1.irc.log" irclog)
string(REGEX MATCH "forward endpoint energy: +(-?[0-9.]+)" _ "${irclog}")
set(E_FWD "${CMAKE_MATCH_1}")
string(REGEX MATCH "backward endpoint energy: +(-?[0-9.]+)" _ "${irclog}")
set(E_BWD "${CMAKE_MATCH_1}")
if(NOT E_FWD OR NOT E_BWD)
  message(FATAL_ERROR "the IRC log reports no endpoint energies\n${irclog}")
endif()
if(E_FWD STREQUAL E_BWD)
  message(FATAL_ERROR "both directions reached the same energy (${E_FWD})")
endif()
# the phase component and the frozen temperature are recorded in the log
if(NOT irclog MATCHES "phase component [(]forward[)]: +([0-9.]+)")
  message(FATAL_ERROR "irc.log does not record the phase component\n${irclog}")
endif()
if(NOT irclog MATCHES "electronic temperature [(]frozen[)]: +300[.]000 K")
  message(FATAL_ERROR "irc.log does not record the effective etemp\n${irclog}")
endif()
# --- golden values of the Gonzalez-Schlegel baseline (report 44 section 3) ---
# The endpoints are pinned to their measured values with a 1e-4 Eh half width:
# the measured spread of the same basin over the four methods at this step
# length is 5.0e-5 Eh (gs -5.47213551 / lqa -5.47215487 / hpc -5.47210457),
# while the only method outside the basin (eulerpc, -5.47130320) is 8.0e-4 Eh
# away, so the window is 2x the observed scatter and 8x narrower than the
# spread it has to exclude.  This is the CLI anchor the earlier version of the
# check lacked (LOW-9 of the M6 review): without it a regression of the
# reported numbers is invisible at the CLI level.
#
# The windows are the measured minima +/- 1e-4 Eh: HNC -5.47215988, HCN
# -5.50406622 (relaxed endpoints of the same run).
function(check_basin label value lower upper)
  if(${value} GREATER ${upper})
    message(FATAL_ERROR "${label} endpoint ${${value}} is above the basin window (${lower} .. ${upper})")
  endif()
  if(${value} LESS ${lower})
    message(FATAL_ERROR "${label} endpoint ${${value}} is below the basin window (${lower} .. ${upper})")
  endif()
endfunction()
check_basin("forward" E_FWD "-5.47225988" "-5.47205988")
check_basin("backward" E_BWD "-5.50416622" "-5.50396622")
if(NOT irclog MATCHES "forward arc length: +4[.]051234")
  message(FATAL_ERROR "the GS forward arc length is no longer 4.051234\n${irclog}")
endif()
if(NOT irclog MATCHES "backward arc length: +3[.]695670")
  message(FATAL_ERROR "the GS backward arc length is no longer 3.695670\n${irclog}")
endif()
if(NOT irclog MATCHES "mean energy/gradient evaluations per point: +16[.]9")
  message(FATAL_ERROR "the GS forward E/g is no longer 16.9\n${irclog}")
endif()
if(NOT irclog MATCHES "mean energy/gradient evaluations per point: +20[.]2")
  message(FATAL_ERROR "the GS backward E/g is no longer 20.2\n${irclog}")
endif()
# the GS defect is demonstrated, not only described: the sphere relaxation is
# pinned at the micro cycle budget on the forward **and** the backward path
if(NOT irclog MATCHES "pinned at the micro cycle budget: forward ([0-9]+) of")
  message(FATAL_ERROR "irc.log does not report the pinned micro cycles\n${irclog}")
endif()
set(PINNED_FWD "${CMAKE_MATCH_1}")
if(PINNED_FWD LESS 1)
  message(FATAL_ERROR "the GS forward sphere relaxation is no longer pinned (${PINNED_FWD} of the points); the recorded cost of GS has to be updated")
endif()
if(NOT irclog MATCHES "backward ([0-9]+) of [0-9]+ points")
  message(FATAL_ERROR "irc.log does not report the pinned backward micro cycles\n${irclog}")
endif()
set(PINNED_BWD "${CMAKE_MATCH_1}")
if(PINNED_BWD LESS 1)
  message(FATAL_ERROR "the GS backward sphere relaxation is no longer pinned (${PINNED_BWD})")
endif()
# determinism: the same input twice has to give a bitwise identical forward path
file(READ "${RUNDIR}/irc1.irc_forward.xyz" first_run)
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/irc0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
          --norestart --namespace irc1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the repeated --lirc run failed with status ${status}\n${output}")
endif()
file(READ "${RUNDIR}/irc1.irc_forward.xyz" second_run)
if(NOT first_run STREQUAL second_run)
  message(FATAL_ERROR "irc_forward.xyz is not bitwise reproducible")
endif()
# `--lirc-step` has to reach the settings (the printed step length)
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/irc0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
          --lirc-step 0.2 --norestart --namespace irc2
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lirc --lirc-step 0.2 failed with status ${status}\n${output}")
endif()
if(NOT output MATCHES "step length: +2[.]000000E-01")
  message(FATAL_ERROR "--lirc-step 0.2 did not reach the settings\n${output}")
endif()
# `--lirc-oneway` runs the forward direction only
foreach(name "irc3.irc_forward.xyz" "irc3.irc_backward.xyz")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/irc0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
          --lirc-oneway --norestart --namespace irc3
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lirc --lirc-oneway failed with status ${status}\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/irc3.irc_forward.xyz")
  message(FATAL_ERROR "--lirc-oneway wrote no forward path\n${output}")
endif()
if(EXISTS "${RUNDIR}/irc3.irc_backward.xyz")
  message(FATAL_ERROR "--lirc-oneway wrote a backward path")
endif()
]=])
add_test("xtb/landscape-irc-cli"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-irc
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc.cmake")

# Landscape suite: the IRC endpoint knobs really change the result (M-1 of
# `45-m6-independent-review.md`).  Two flags used to be parsed and then never
# read (`--lirc-level`, `--lirc-rmsd-end`), and the default method was `gs`
# although the validation round measured `hpc` better and 8.5x cheaper.  This
# check is self contained (it converges its own transition state) and is the
# executable evidence for all three: each flag has to make the reported
# numbers move, the default has to be `hpc`, and the sphere relaxation counter
# of the predictor-corrector has to stay at zero.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_knobs.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method prfo --norestart
          --namespace ircknob0
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the preparation --lts run failed with status ${status}\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/ircknob0.xtbts.xyz")
  message(FATAL_ERROR "the preparation --lts run wrote no xtbts.xyz\n${output}")
endif()
# the windows are the measured minima +/- 1e-4 Eh (HNC -5.47215988, HCN
# -5.50406622); see `xtb/landscape-irc-cli` for the derivation
function(check_basin label value lower upper)
  if(${value} GREATER ${upper})
    message(FATAL_ERROR "${label} endpoint ${${value}} is above the basin window (${lower} .. ${upper})")
  endif()
  if(${value} LESS ${lower})
    message(FATAL_ERROR "${label} endpoint ${${value}} is below the basin window (${lower} .. ${upper})")
  endif()
endfunction()
# --- the default method is hpc (M6 behaviour change, PLAN section 12.15) ---
# `--lirc` without `--lirc-method` must really run the predictor-corrector; a
# default that is not covered end to end would be another dead knob.
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/ircknob0.xtbts.xyz" --gfn 2 --lirc --norestart
          --namespace irc4
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lirc without --lirc-method failed with status ${status}\n${output}")
endif()
file(READ "${RUNDIR}/irc4.irc.log" deflog)
if(NOT deflog MATCHES "intrinsic reaction coordinate: hpc")
  message(FATAL_ERROR "the default IRC method is no longer hpc\n${deflog}")
endif()
string(REGEX MATCH "forward endpoint energy: +(-?[0-9.]+)" _ "${deflog}")
set(DE_E_FWD "${CMAKE_MATCH_1}")
string(REGEX MATCH "backward endpoint energy: +(-?[0-9.]+)" _ "${deflog}")
set(DE_E_BWD "${CMAKE_MATCH_1}")
check_basin("default forward" DE_E_FWD "-5.47225988" "-5.47205988")
check_basin("default backward" DE_E_BWD "-5.50416622" "-5.50396622")
# negative control of the pinned counter: the predictor-corrector has no sphere
# relaxation, so no point may be pinned
if(NOT deflog MATCHES "pinned at the micro cycle budget: forward 0 of")
  message(FATAL_ERROR "the default (hpc) run reports pinned micro cycles\n${deflog}")
endif()
# --- `--lirc-rmsd-end` really attributes the endpoint (MEDIUM-1) ---
# The forward endpoint is 0.0099 bohr away from its relaxed minimum (measured),
# so a threshold of 1e-3 has to reject it while the backward endpoint (1.6e-5)
# stays assigned.  Without the criterion the flag changes nothing.
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/ircknob0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
          --lirc-rmsd-end 1e-3 --norestart --namespace irc5
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lirc --lirc-rmsd-end 1e-3 failed with status ${status}\n${output}")
endif()
file(READ "${RUNDIR}/irc5.irc.log" rmsdlog)
if(NOT rmsdlog MATCHES "endpoint rmsd criterion: rmsd <= rmsd_end = 0[.]00100000")
  message(FATAL_ERROR "--lirc-rmsd-end 1e-3 did not reach the settings\n${rmsdlog}")
endif()
if(NOT rmsdlog MATCHES "forward reached minimum: +F")
  message(FATAL_ERROR "--lirc-rmsd-end 1e-3 did not reject the forward endpoint\n${rmsdlog}")
endif()
if(NOT rmsdlog MATCHES "backward reached minimum: +T")
  message(FATAL_ERROR "--lirc-rmsd-end 1e-3 rejected the backward endpoint\n${rmsdlog}")
endif()
# --- `--lirc-level` really drives the endpoint relaxation (MEDIUM-1) ---
# Measured with the GS path: superloose relaxes the forward endpoint in 1 step
# to -5.47213843 Eh, vtight in 7 steps to -5.47215989 Eh.  Both the step count
# and the energy of the relaxed minimum have to react to the flag.
foreach(level "superloose" "vtight")
  execute_process(
    COMMAND "${EXE}" "${RUNDIR}/ircknob0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
            --lirc-level ${level} --norestart --namespace irc-${level}
    WORKING_DIRECTORY "${RUNDIR}"
    RESULT_VARIABLE status
    OUTPUT_VARIABLE output
    ERROR_VARIABLE output
  )
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "xtb --lirc-level ${level} failed with status ${status}\n${output}")
  endif()
  file(READ "${RUNDIR}/irc-${level}.irc.log" levellog)
  if(NOT levellog MATCHES "forward relaxed minimum: +(-?[0-9.]+) Eh [(]([0-9]+) relaxation steps[)]")
    message(FATAL_ERROR "the ${level} log reports no relaxed minimum\n${levellog}")
  endif()
  set(E_${level} "${CMAKE_MATCH_1}")
  set(N_${level} "${CMAKE_MATCH_2}")
  message(STATUS "--lirc-level ${level}: forward minimum ${CMAKE_MATCH_1} Eh after ${CMAKE_MATCH_2} steps")
endforeach()
if(N_superloose GREATER_EQUAL N_vtight)
  message(FATAL_ERROR "--lirc-level vtight did not need more relaxation steps than superloose (${N_vtight} vs ${N_superloose})")
endif()
if(E_vtight GREATER_EQUAL E_superloose)
  message(FATAL_ERROR "--lirc-level vtight did not relax further than superloose (${E_vtight} vs ${E_superloose})")
endif()
# --- `--lirc-no-endpoint-relax` (the documented fallback of the criterion) ---
# Without a relaxation there is no relaxed minimum: `reached_min` falls back to
# the termination signal and the log has to say so instead of printing a
# satisfied distance check (M-2 of the M6 review).
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/ircknob0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
          --lirc-no-endpoint-relax --norestart --namespace irc6
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lirc --lirc-no-endpoint-relax failed with status ${status}\n${output}")
endif()
file(READ "${RUNDIR}/irc6.irc.log" norelaxlog)
if(NOT norelaxlog MATCHES "forward reached minimum: +T")
  message(FATAL_ERROR "--lirc-no-endpoint-relax lost the termination based attribution\n${norelaxlog}")
endif()
if(norelaxlog MATCHES "forward relaxed minimum:")
  message(FATAL_ERROR "--lirc-no-endpoint-relax still reports a relaxed minimum\n${norelaxlog}")
endif()
if(NOT norelaxlog MATCHES "the rmsd_end criterion was skipped")
  message(FATAL_ERROR "--lirc-no-endpoint-relax does not report the skipped rmsd criterion\n${norelaxlog}")
endif()
]=])
add_test("xtb/landscape-irc-knobs"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-irc-knobs
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_knobs.cmake")

# Landscape suite: `--lirc-swap` exchanges the two directions defined by the
# phase convention.  The forward endpoint of the plain run is the backward
# endpoint of the swapped run, so the two endpoint energies are exchanged.
# The script converges the transition state itself, so the test is independent
# of the order ctest runs the landscape checks in.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_swap.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
# converge the transition state (self-contained, see `xtb/landscape-irc-cli`)
execute_process(
  COMMAND "${EXE}" "${GUESS}" --gfn 2 --lts --lts-method prfo --norestart
          --namespace ircswap0
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the preparation --lts run failed with status ${status}\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/ircswap0.xtbts.xyz")
  message(FATAL_ERROR "the preparation --lts run wrote no xtbts.xyz\n${output}")
endif()
function(run_case args suffix)
  execute_process(
    COMMAND "${EXE}" "${RUNDIR}/ircswap0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
            --norestart --namespace ${suffix} ${args}
    WORKING_DIRECTORY "${RUNDIR}"
    RESULT_VARIABLE status
    OUTPUT_VARIABLE output
    ERROR_VARIABLE output
  )
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "xtb --lirc ${args} failed with status ${status}\n${output}")
  endif()
  file(READ "${RUNDIR}/${suffix}.irc.log" log)
  string(REGEX MATCH "forward endpoint energy: +(-?[0-9.]+)" _ "${log}")
  set(${suffix}_fwd "${CMAKE_MATCH_1}" PARENT_SCOPE)
  string(REGEX MATCH "backward endpoint energy: +(-?[0-9.]+)" _ "${log}")
  set(${suffix}_bwd "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()
run_case("" ircswap1)
run_case("--lirc-swap" ircswap2)
if(NOT ircswap1_fwd OR NOT ircswap1_bwd)
  message(FATAL_ERROR "the plain run reports no endpoint energies")
endif()
if(ircswap1_fwd STREQUAL ircswap1_bwd)
  message(FATAL_ERROR "both directions reached the same energy (${ircswap1_fwd}); the swap check would be vacuous")
endif()
if(NOT ircswap1_fwd STREQUAL ircswap2_bwd)
  message(FATAL_ERROR "--lirc-swap did not exchange the forward endpoint: ${ircswap1_fwd} vs ${ircswap2_bwd}")
endif()
if(NOT ircswap1_bwd STREQUAL ircswap2_fwd)
  message(FATAL_ERROR "--lirc-swap did not exchange the backward endpoint: ${ircswap1_bwd} vs ${ircswap2_fwd}")
endif()
]=])
add_test("xtb/landscape-irc-swap"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DGUESS=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-irc-swap
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_swap.cmake")

# Landscape suite: termination signal (c) at the command line.  With the
# gradient threshold disabled (`--lirc-grad-tol 0`) the only physical signal
# left is the energy rise, so both directions have to terminate with
# `energy_rise` and still be assigned to a minimum.  This is the endpoint
# attribution check of the PLAN experiment 7 and the client of the signal (c)
# branch (a run with the default threshold terminates by signal (b) first, so
# the default `xtb/landscape-irc-cli` cannot see the difference).
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_termination.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${GUESS}" --gfn 2 --lts --lts-method prfo --norestart
          --namespace ircterm0
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the preparation --lts run failed with status ${status}\n${output}")
endif()
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/ircterm0.xtbts.xyz" --gfn 2 --lirc --lirc-method gs
          --lirc-grad-tol 0 --norestart --namespace ircterm1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lirc --lirc-grad-tol 0 failed with status ${status}\n${output}")
endif()
if(NOT output MATCHES "termination forward: +energy_rise")
  message(FATAL_ERROR "the forward direction did not terminate by signal (c)\n${output}")
endif()
if(NOT output MATCHES "termination backward: +energy_rise")
  message(FATAL_ERROR "the backward direction did not terminate by signal (c)\n${output}")
endif()
if(NOT output MATCHES "forward reached minimum: +T")
  message(FATAL_ERROR "the forward endpoint is not assigned to a minimum\n${output}")
endif()
if(NOT output MATCHES "backward reached minimum: +T")
  message(FATAL_ERROR "the backward endpoint is not assigned to a minimum\n${output}")
endif()
if(NOT output MATCHES "landscape engine: etemp +300[.]000 K")
  message(FATAL_ERROR "the frozen electronic temperature was not reported\n${output}")
endif()
]=])
add_test("xtb/landscape-irc-termination"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DGUESS=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-irc-termination
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_termination.cmake")

# Landscape suite: the predictor-corrector integrators (`--lirc-method hpc` and
# `--lirc-method eulerpc`, M6 phase 2).  Both have to confirm exactly one
# imaginary mode, reach a minimum in both directions, write the four output
# files and keep the per point energy/gradient cost at the predictor-corrector
# level (two E/g per point on the converged path).  The same script also
# exercises the new `--lirc-loose-cycles` and `--lirc-erise-steps` flags.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_pc.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${GUESS}" --gfn 2 --lts --lts-method prfo --norestart
          --namespace ircpc0
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the preparation --lts run failed with status ${status}\n${output}")
endif()
foreach(method "hpc" "eulerpc")
  foreach(name "${method}.irc_forward.xyz" "${method}.irc_backward.xyz" "${method}.irc_path.xyz" "${method}.irc.log")
    if(EXISTS "${RUNDIR}/${name}")
      file(REMOVE "${RUNDIR}/${name}")
    endif()
  endforeach()
  execute_process(
    COMMAND "${EXE}" "${RUNDIR}/ircpc0.xtbts.xyz" --gfn 2 --lirc --lirc-method ${method}
            --norestart --namespace ${method}
    WORKING_DIRECTORY "${RUNDIR}"
    RESULT_VARIABLE status
    OUTPUT_VARIABLE output
    ERROR_VARIABLE output
  )
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "xtb --lirc --lirc-method ${method} failed with status ${status}\n${output}")
  endif()
  if(NOT output MATCHES "landscape: intrinsic reaction coordinate [(]${method}[)]")
    message(FATAL_ERROR "the ${method} IRC header was not printed\n${output}")
  endif()
  if(NOT output MATCHES "transition state imaginary modes: +1")
    message(FATAL_ERROR "${method}: the transition state was not confirmed\n${output}")
  endif()
  if(NOT output MATCHES "termination forward: +(gradient|energy_rise)")
    message(FATAL_ERROR "${method}: the forward direction did not reach a stationary point\n${output}")
  endif()
  if(NOT output MATCHES "termination backward: +(gradient|energy_rise)")
    message(FATAL_ERROR "${method}: the backward direction did not reach a stationary point\n${output}")
  endif()
  if(NOT output MATCHES "forward reached minimum: +T")
    message(FATAL_ERROR "${method}: the forward endpoint is not assigned to a minimum\n${output}")
  endif()
  if(NOT output MATCHES "backward reached minimum: +T")
    message(FATAL_ERROR "${method}: the backward endpoint is not assigned to a minimum\n${output}")
  endif()
  foreach(name "${method}.irc_forward.xyz" "${method}.irc_backward.xyz" "${method}.irc_path.xyz" "${method}.irc.log")
    if(NOT EXISTS "${RUNDIR}/${name}")
      message(FATAL_ERROR "${name} was not written")
    endif()
    file(SIZE "${RUNDIR}/${name}" size)
    if(size EQUAL 0)
      message(FATAL_ERROR "${name} is empty")
    endif()
  endforeach()
  file(READ "${RUNDIR}/${method}.irc.log" log)
  string(REGEX MATCH "mean energy/gradient evaluations per point: +([0-9.]+)" _ "${log}")
  set(mean_ev "${CMAKE_MATCH_1}")
  if(NOT mean_ev)
    message(FATAL_ERROR "${method}: the log reports no mean E/g\n${log}")
  endif()
  # the predictor-corrector costs a small integer number of E/g per point; the
  # upper bound guards against a regression towards the 16.9-20.3 of the GS
  # micro-cycle relaxer
  if(mean_ev GREATER 6.0)
    message(FATAL_ERROR "${method}: the mean E/g per point is ${mean_ev}, far above the predictor-corrector level\n${log}")
  endif()
  if(NOT log MATCHES "forward endpoint energy: +-5[.]47")
    message(FATAL_ERROR "${method}: the forward endpoint did not reach the HNC basin\n${log}")
  endif()
  if(NOT log MATCHES "backward endpoint energy: +-5[.]50")
    message(FATAL_ERROR "${method}: the backward endpoint did not reach the HCN basin\n${log}")
  endif()
endforeach()
# `--lirc-loose-cycles 0` reaches the EulerPC settings (the coarse phase off)
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/ircpc0.xtbts.xyz" --gfn 2 --lirc --lirc-method eulerpc
          --lirc-loose-cycles 0 --norestart --namespace epc1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the --lirc-loose-cycles 0 run failed with status ${status}\n${output}")
endif()
# `--lirc-erise-steps` (the alias of --lirc-e-rise) reaches the EulerPC settings
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/ircpc0.xtbts.xyz" --gfn 2 --lirc --lirc-method eulerpc
          --lirc-erise-steps 5 --lirc-grad-tol 0 --norestart --namespace epc2
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the --lirc-erise-steps run failed with status ${status}\n${output}")
endif()
# a path cut off by the step budget must NOT be assigned to a minimum
# (the endpoint assignment is the client of `endpoint_reached`)
execute_process(
  COMMAND "${EXE}" "${RUNDIR}/ircpc0.xtbts.xyz" --gfn 2 --lirc --lirc-method hpc
          --lirc-max-steps 3 --norestart --namespace epc3
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the --lirc-max-steps 3 run failed with status ${status}\n${output}")
endif()
if(NOT output MATCHES "termination forward: +max_steps")
  message(FATAL_ERROR "the step budget did not report signal (a)\n${output}")
endif()
if(NOT output MATCHES "forward reached minimum: +F")
  message(FATAL_ERROR "a path cut off by the step budget was assigned to a minimum\n${output}")
endif()
]=])
add_test("xtb/landscape-irc-pc"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DGUESS=${LANDSCAPE-HCN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-irc-pc
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_irc_pc.cmake")

# Landscape suite: the IRC error branches.  An input that is not a first order
# saddle point (water is a minimum) and an unknown method name both have to
# abort with a non-zero status and the documented message.
add_test("xtb/landscape-irc-minimum"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lirc --lirc-method gs"
  "-DPATTERN=not a transition state"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-irc-method-unknown"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-HCN}
  "-DARGS=--gfn 2 --lirc --lirc-method bogus"
  "-DPATTERN=Unknown landscape IRC method"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
# an IRC DWI surface with a single sample point cannot exist (`dwi_n` is a
# capacity and the interpolant is two point by construction): the flag is
# validated instead of silently doing nothing (L-2 of the M6 review)
add_test("xtb/landscape-irc-dwi-n"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-H2O}
  "-DARGS=--gfn 2 --lirc --lirc-dwi-n 1"
  "-DPATTERN=the IRC DWI surface needs at least two sample points"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-error
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# ---------------------------------------------------------------------------
# Landscape suite: chain-of-states band searches (`--lts --lts-method neb`).
#
# The input contract of `landscape_path_settings` is exercised end to end: the
# positional input file is the reactant, `--lts-product` supplies the product
# (a single frame xyz) and every other combination is rejected with a readable
# diagnostic and a non-zero exit status.  The ammonia inversion is a reaction
# with a small, well known barrier whose transition state is a first order
# saddle, so the band run also exercises the frequency confirmation.
set(LANDSCAPE-NH3 "${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_up.xyz")
file(WRITE "${LANDSCAPE-NH3}"
  "4\nammonia (N above the H3 plane)\n"
  "N  0.0000000  0.0000000  0.3800000\n"
  "H  0.9400000  0.0000000  0.0000000\n"
  "H -0.4700000  0.8140000  0.0000000\n"
  "H -0.4700000 -0.8140000  0.0000000\n")
set(LANDSCAPE-NH3-DOWN "${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_down.xyz")
file(WRITE "${LANDSCAPE-NH3-DOWN}"
  "4\nammonia (N below the H3 plane)\n"
  "N  0.0000000  0.0000000 -0.3800000\n"
  "H  0.9400000  0.0000000  0.0000000\n"
  "H -0.4700000  0.8140000  0.0000000\n"
  "H -0.4700000 -0.8140000  0.0000000\n")
# a product with three atoms instead of four
set(LANDSCAPE-NH3-SHORT "${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_short.xyz")
file(WRITE "${LANDSCAPE-NH3-SHORT}"
  "3\nthree atoms only\n"
  "N  0.0000000  0.0000000 -0.3800000\n"
  "H  0.9400000  0.0000000  0.0000000\n"
  "H -0.4700000  0.8140000  0.0000000\n")
# a product with the right number of atoms in the wrong order
set(LANDSCAPE-NH3-ORDER "${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_order.xyz")
file(WRITE "${LANDSCAPE-NH3-ORDER}"
  "4\nwrong atom order\n"
  "H  0.9400000  0.0000000  0.0000000\n"
  "N  0.0000000  0.0000000 -0.3800000\n"
  "H -0.4700000  0.8140000  0.0000000\n"
  "H -0.4700000 -0.8140000  0.0000000\n")
# a product file that holds two frames
file(READ "${LANDSCAPE-NH3-DOWN}" NH3-DOWN-CONTENT)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_two.xyz"
  "${NH3-DOWN-CONTENT}${NH3-DOWN-CONTENT}")
# an input file that holds two frames
file(READ "${LANDSCAPE-NH3}" NH3-UP-CONTENT)
set(LANDSCAPE-NH3-TWO-FRAME "${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_two_in.xyz")
file(WRITE "${LANDSCAPE-NH3-TWO-FRAME}"
  "${NH3-UP-CONTENT}${NH3-DOWN-CONTENT}")
# a product with a non xyz extension
set(LANDSCAPE-NH3-COORD "${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_product.coord")
file(WRITE "${LANDSCAPE-NH3-COORD}"
  "$coord\n"
  " 0.00000000000000  0.00000000000000 -0.38000000000000  n\n"
  " 0.94000000000000  0.00000000000000  0.00000000000000  h\n"
  "-0.47000000000000  0.81400000000000  0.00000000000000  h\n"
  "-0.47000000000000 -0.81400000000000  0.00000000000000  h\n")

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_path.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "p1.path.xyz" "p1.xtbts.xyz" "p1.xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method neb --lts-images 7
          --lts-product "${PRODUCT}" --norestart --namespace p1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method neb terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: transition state search [(]neb[)]")
  message(FATAL_ERROR "the band header was not printed\n${output}")
endif()
if(NOT output MATCHES "band: k_min")
  message(FATAL_ERROR "the band settings were not printed\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "the band did not converge\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the transition state candidate is not a first order saddle\n${output}")
endif()
if(NOT output MATCHES "landscape task terminated")
  message(FATAL_ERROR "the band task did not terminate\n${output}")
endif()
foreach(name "p1.path.xyz" "p1.xtbts.xyz" "p1.xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
# one frame per image, frame 1 the reactant and frame 7 the product
file(READ "${RUNDIR}/p1.path.xyz" pathfile)
string(REGEX MATCHALL "energy:" frames "${pathfile}")
list(LENGTH frames nframes)
if(NOT nframes EQUAL 7)
  message(FATAL_ERROR "path.xyz holds ${nframes} frames, expected 7")
endif()
# the climbing image variant has to converge as well
file(REMOVE "${RUNDIR}/p1.path.xyz")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method cineb --lts-images 7
          --lts-product "${PRODUCT}" --norestart --namespace p1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method cineb terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "climbing image [0-9]+ ignited at iteration")
  message(FATAL_ERROR "the climbing image was never ignited\n${output}")
endif()
if(NOT output MATCHES "band: climbing image [(]TS candidate[)]: [0-9]+")
  message(FATAL_ERROR "the climbing image was not reported\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the CI-NEB candidate is not a first order saddle\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/p1.path.xyz")
  message(FATAL_ERROR "path.xyz was not written by the CI-NEB run")
endif()
# `--lts-relax-ends` relaxes the two endpoints with the M1 minimiser before the
# band is built: the printed gradient norm has to drop **for both endpoints**
# and the band still has to converge (report 38 L-11, which had no coverage at
# all; the before/after comparison is R2-L3)
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method cineb --lts-images 7
          --lts-product "${PRODUCT}" --lts-relax-ends
          --norestart --namespace p1
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-relax-ends terminated with status ${status}\n${output}")
endif()
string(REGEX MATCH "band: endpoint relaxation [(]reactant[)] before: +E +(-?[0-9.]+) Eh, [|]g[|] +([0-9.E+-]+)" _ "${output}")
if(NOT CMAKE_MATCH_1)
  message(FATAL_ERROR "the reactant was not reported before the relaxation\n${output}")
endif()
set(REACTANT-G-BEFORE "${CMAKE_MATCH_2}")
string(REGEX MATCH "band: endpoint relaxation [(]reactant[)] after: +E +(-?[0-9.]+) Eh, [|]g[|] +([0-9.E+-]+)" _ "${output}")
if(NOT CMAKE_MATCH_1)
  message(FATAL_ERROR "the relaxed reactant was not reported\n${output}")
endif()
set(REACTANT-G-AFTER "${CMAKE_MATCH_2}")
string(REGEX MATCH "band: endpoint relaxation [(]product[)] before: +E +(-?[0-9.]+) Eh, [|]g[|] +([0-9.E+-]+)" _ "${output}")
if(NOT CMAKE_MATCH_1)
  message(FATAL_ERROR "the product was not reported before the relaxation\n${output}")
endif()
set(PRODUCT-G-BEFORE "${CMAKE_MATCH_2}")
string(REGEX MATCH "band: endpoint relaxation [(]product[)] after: +E +(-?[0-9.]+) Eh, [|]g[|] +([0-9.E+-]+)" _ "${output}")
if(NOT CMAKE_MATCH_1)
  message(FATAL_ERROR "the relaxed product was not reported\n${output}")
endif()
set(PRODUCT-G-AFTER "${CMAKE_MATCH_2}")
# the relaxation has to **lower** the gradient norm of both endpoints (each is a
# minimum of the free surface, so the M1 minimiser has to descend).  Checking
# only that the two lines exist lets a relaxation that is a no-op stay green
# (report 38 L-11, R2-L3).
if(NOT REACTANT-G-AFTER LESS REACTANT-G-BEFORE)
  message(FATAL_ERROR "the reactant relaxation did not lower the gradient norm: ${REACTANT-G-BEFORE} -> ${REACTANT-G-AFTER}\n${output}")
endif()
if(NOT PRODUCT-G-AFTER LESS PRODUCT-G-BEFORE)
  message(FATAL_ERROR "the product relaxation did not lower the gradient norm: ${PRODUCT-G-BEFORE} -> ${PRODUCT-G-AFTER}\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "the band with relaxed endpoints did not converge\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the relaxed-endpoint band did not confirm the saddle\n${output}")
endif()
]=])
add_test("xtb/landscape-path-cli"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-NH3}
  -DPRODUCT=${LANDSCAPE-NH3-DOWN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-path
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_path.cmake")

set(LANDSCAPE-PATH-DIR "${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-path")
add_test("xtb/landscape-path-product-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5"
  "-DPATTERN=a band search needs a product geometry"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-product-not-found"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5 --lts-product no_such_product.xyz"
  "-DPATTERN=cannot open the product geometry"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-product-atom-count"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5 --lts-product ${LANDSCAPE-NH3-SHORT}"
  "-DPATTERN=the product geometry has 3 atoms but the reactant has 4"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-product-atom-order"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5 --lts-product ${LANDSCAPE-NH3-ORDER}"
  "-DPATTERN=the atom order of the product geometry differs"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-product-multiframe"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5 --lts-product ${CMAKE_CURRENT_BINARY_DIR}/landscape_nh3_two.xyz"
  "-DPATTERN=holds 2 frames; exactly one is required"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-product-not-xyz"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5 --lts-product ${LANDSCAPE-NH3-COORD}"
  "-DPATTERN=must be a single frame xyz file"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-input-multiframe"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3-TWO-FRAME}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5"
  "-DPATTERN=the input holds 2 frames; pass the product with --lts-product"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-ambiguous"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3-TWO-FRAME}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images 5 --lts-product ${LANDSCAPE-NH3-DOWN}"
  "-DPATTERN=the two endpoints are ambiguous"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-band-images-missing"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method neb --lts-images"
  "-DPATTERN=The --lts-images flag requires an integer"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# A global `--lts-product` is ignored by the single ended methods; the run
# must say so instead of ignoring the option silently.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_path_warn.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method dimer --lts-ninit force
          --lts-product "${PRODUCT}" --norestart
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT output MATCHES "only used by")
  message(FATAL_ERROR "the ignored --lts-product was not reported\n${output}")
endif()
if(NOT output MATCHES "neb|cineb")
  message(FATAL_ERROR "the warning does not name the band methods\n${output}")
endif()
]=])
add_test("xtb/landscape-path-product-single-ended"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-HCN}
  -DPRODUCT=${LANDSCAPE-NH3-DOWN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-path-warn
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_path_warn.cmake")

# Landscape suite: end to end AutoNEB.  The coarse path of five images is grown
# to the requested nine images by inserting one image per stage at the interval
# of the worst energy resolution, and the resulting saddle candidate has to be
# the first order saddle of the ammonia inversion.  The path of the first run
# is then read back with `--lts-autoneb-restart`: the already completed stages
# are not repeated, so the restarted run must reproduce the barrier and the
# number of images of the uninterrupted one.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_autoneb.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "p2.path_autoneb.xyz" "p2.path_ts_list.xyz" "p2.xtbts.xyz" "p2.xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method autoneb
          --lts-product "${PRODUCT}" --lts-max-steps 400 --norestart --namespace p2
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method autoneb terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: transition state search [(]autoneb[)]")
  message(FATAL_ERROR "the AutoNEB header was not printed\n${output}")
endif()
if(NOT output MATCHES "autoneb: coarse path of 5 images, target 9")
  message(FATAL_ERROR "the coarse path of the AutoNEB run was not reported\n${output}")
endif()
if(NOT output MATCHES "autoneb: 5 stages, 4 inserted images, 9 images in the final path")
  message(FATAL_ERROR "the AutoNEB stages were not completed\n${output}")
endif()
if(NOT output MATCHES "autoneb: inserted an image")
  message(FATAL_ERROR "no image was inserted\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "the AutoNEB path did not converge\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the AutoNEB candidate is not a first order saddle\n${output}")
endif()
foreach(name "p2.path_autoneb.xyz" "p2.path_ts_list.xyz" "p2.xtbts.xyz" "p2.xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
# one frame per image of the final path
file(READ "${RUNDIR}/p2.path_autoneb.xyz" autonebfile)
string(REGEX MATCHALL "energy:" frames "${autonebfile}")
list(LENGTH frames nframes)
if(NOT nframes EQUAL 9)
  message(FATAL_ERROR "path_autoneb.xyz holds ${nframes} frames, expected 9")
endif()
# one saddle candidate per completed stage, each with its imaginary mode count
file(READ "${RUNDIR}/p2.path_ts_list.xyz" tslist)
string(REGEX MATCHALL "imaginary modes:" candidates "${tslist}")
list(LENGTH candidates ncand)
if(NOT ncand EQUAL 5)
  message(FATAL_ERROR "path_ts_list.xyz holds ${ncand} candidates, expected 5")
endif()
string(REGEX MATCHALL "imaginary modes: 1" saddles "${tslist}")
list(LENGTH saddles nsaddle)
if(NOT nsaddle EQUAL 5)
  message(FATAL_ERROR "only ${nsaddle} of the AutoNEB candidates is a first order saddle")
endif()
# take the barrier of the uninterrupted run
string(REGEX MATCH "autoneb: saddle candidate +-?[0-9.]+ Eh, barrier +([0-9.]+)" _ "${output}")
set(BARRIER "${CMAKE_MATCH_1}")
# the path file of the uninterrupted run, normalised for the comparison below.
# Two normalisations: the stage counter in the frame comments is not reproduced
# by the restart (it does not repeat the stages), and every number is truncated
# to four decimals.  The second is required because the adopted path goes
# through the text file and is **not** bitwise equal to the in-memory result
# (report 38 L-12; measured in report 39 section 10 item 4: the largest
# difference is 2e-5 angstrom and comes from the Kabsch alignment that the band
# applies to the adopted images, and the two saddle energies differ in the 12th
# decimal).  A negative zero is normalised as well, because the sign of a
# coordinate at the level of the round trip is not reproducible.
file(READ "${RUNDIR}/p2.path_autoneb.xyz" ONESHOTPATH)
string(REGEX REPLACE "iter: [0-9]+" "iter:" ONESHOTPATH "${ONESHOTPATH}")
# (a `{4}` quantifier is not supported by the CMake regex engine, hence the
# explicit repetition of the digit class)
string(REGEX REPLACE "(-?[0-9]+[.][0-9][0-9][0-9][0-9])[0-9]+" "\\1" ONESHOTPATH "${ONESHOTPATH}")
string(REGEX REPLACE "-0[.]0000" "0.0000" ONESHOTPATH "${ONESHOTPATH}")
string(REGEX REPLACE "  +" " " ONESHOTPATH "${ONESHOTPATH}")
# the restart: the path of the run above is adopted as the initial path, so no
# insertion is left (the target of 9 images is already reached)
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method autoneb
          --lts-product "${PRODUCT}" --lts-max-steps 400 --norestart --namespace p2
          --lts-autoneb-restart "${RUNDIR}/p2.path_autoneb.xyz"
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the restarted AutoNEB run terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "autoneb: 1 stages, 0 inserted images, 9 images in the final path")
  message(FATAL_ERROR "the restart repeated a stage\n${output}")
endif()
string(REGEX MATCH "autoneb: saddle candidate +-?[0-9.]+ Eh, barrier +([0-9.]+)" _ "${output}")
if(NOT "${CMAKE_MATCH_1}" STREQUAL "${BARRIER}")
  message(FATAL_ERROR "the restart changed the barrier: ${BARRIER} -> ${CMAKE_MATCH_1}")
endif()
# frame by frame comparison of the path file: the restarted run has to
# reproduce the path of the uninterrupted one (same frames, same atom order,
# same energies and geometries to the printed precision)
file(READ "${RUNDIR}/p2.path_autoneb.xyz" RESTARTEDPATH)
string(REGEX REPLACE "iter: [0-9]+" "iter:" RESTARTEDPATH "${RESTARTEDPATH}")
string(REGEX REPLACE "(-?[0-9]+[.][0-9][0-9][0-9][0-9])[0-9]+" "\\1" RESTARTEDPATH "${RESTARTEDPATH}")
string(REGEX REPLACE "-0[.]0000" "0.0000" RESTARTEDPATH "${RESTARTEDPATH}")
string(REGEX REPLACE "  +" " " RESTARTEDPATH "${RESTARTEDPATH}")
if(NOT ONESHOTPATH STREQUAL RESTARTEDPATH)
  message(FATAL_ERROR "the restarted AutoNEB run did not reproduce path_autoneb.xyz")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the restarted run did not confirm the saddle\n${output}")
endif()
]=])
add_test("xtb/landscape-path-autoneb"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-NH3}
  -DPRODUCT=${LANDSCAPE-NH3-DOWN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-autoneb
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_autoneb.cmake")

# Landscape suite: end to end growing string.  The two convergence thresholds
# are relaxed with respect to the band defaults because the discrete string has
# a resolution floor: measured on this run, the largest per node perpendicular
# force of the string is 1.9e-3 while the band default is 1e-3 (report 36
# section 5).  The run has to grow the string, converge it, refine the climbing
# node and write path.xyz and path_ts_list.xyz.
#
# The growth numbers changed with the M-2 fix of the first growth direction
# (report 39 section 8.2): the string now grows 8 steps to 10 nodes (was 6 steps
# to 8 nodes) and reaches a barrier of 6.0702 kcal/mol (was 5.9789, the band
# gives 6.0825, so the two legs of the cross validation agree to 0.012 kcal/mol
# instead of 0.104).
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_string.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
foreach(name "p3.path.xyz" "p3.path_ts_list.xyz" "p3.xtbts.xyz" "p3.xtbts.log")
  if(EXISTS "${RUNDIR}/${name}")
    file(REMOVE "${RUNDIR}/${name}")
  endif()
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method string
          --lts-product "${PRODUCT}" --lts-string-nnodes 16
          --lts-frms-avg 1e-3 --lts-frms-max 2e-3 --lts-max-steps 600
          --norestart --namespace p3
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method string terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: transition state search [(]string[)]")
  message(FATAL_ERROR "the string header was not printed\n${output}")
endif()
if(NOT output MATCHES "string: growth steps [0-9]+.*spacing")
  message(FATAL_ERROR "the growth of the string was not reported\n${output}")
endif()
if(NOT output MATCHES "string: climbing node [0-9]+ refined in [0-9]+ iterations")
  message(FATAL_ERROR "the climbing node was not refined\n${output}")
endif()
if(NOT output MATCHES "landscape: converged")
  message(FATAL_ERROR "the string did not converge\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the string candidate is not a first order saddle\n${output}")
endif()
foreach(name "p3.path.xyz" "p3.path_ts_list.xyz" "p3.xtbts.xyz" "p3.xtbts.log")
  if(NOT EXISTS "${RUNDIR}/${name}")
    message(FATAL_ERROR "${name} was not written")
  endif()
  file(SIZE "${RUNDIR}/${name}" size)
  if(size EQUAL 0)
    message(FATAL_ERROR "${name} is empty")
  endif()
endforeach()
file(READ "${RUNDIR}/p3.path.xyz" pathfile)
string(REGEX MATCHALL "energy:" frames "${pathfile}")
list(LENGTH frames nframes)
if(nframes LESS 5)
  message(FATAL_ERROR "path.xyz holds only ${nframes} frames")
endif()
file(READ "${RUNDIR}/p3.path_ts_list.xyz" tslist)
string(REGEX MATCHALL "imaginary modes:" candidates "${tslist}")
list(LENGTH candidates ncand)
if(ncand LESS 1)
  message(FATAL_ERROR "path_ts_list.xyz holds no candidate")
endif()
# the GSM variant shares the kernel and must reach the same kind of saddle
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method gsm
          --lts-product "${PRODUCT}" --lts-string-nnodes 16
          --lts-frms-avg 1e-3 --lts-frms-max 2e-3 --lts-max-steps 600
          --norestart --namespace p3
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method gsm terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "landscape: transition state search [(]gsm[)]")
  message(FATAL_ERROR "the gsm header was not printed\n${output}")
endif()
if(NOT output MATCHES "saddle confirmation - imaginary modes: 1")
  message(FATAL_ERROR "the gsm candidate is not a first order saddle\n${output}")
endif()
# cross check: the string and the band kernel have to agree on the barrier of
# the same reaction (the measured difference is 0.10 kcal/mol)
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method cineb --lts-images 9
          --lts-product "${PRODUCT}" --lts-max-steps 400 --norestart --namespace p4
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lts --lts-method cineb terminated with status ${status}\n${output}")
endif()
string(REGEX MATCH "band: highest image +[0-9]+, energy +-?[0-9.]+ Eh, barrier +([0-9.]+)" _ "${output}")
set(NEBBARRIER "${CMAKE_MATCH_1}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method string
          --lts-product "${PRODUCT}" --lts-string-nnodes 16
          --lts-frms-avg 1e-3 --lts-frms-max 2e-3 --lts-max-steps 600
          --norestart --namespace p4
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the cross check string run terminated with status ${status}\n${output}")
endif()
string(REGEX MATCH "string: path length +[0-9.]+ bohr, highest node +[0-9]+, E +-?[0-9.]+ Eh, barrier +([0-9.]+)" _ "${output}")
set(STRINGBARRIER "${CMAKE_MATCH_1}")
if(NOT NEBBARRIER MATCHES "^[0-9]+" OR NOT STRINGBARRIER MATCHES "^[0-9]+")
  message(FATAL_ERROR "a barrier was not found: band '${NEBBARRIER}', string '${STRINGBARRIER}'\n${output}")
endif()
execute_process(COMMAND ${CMAKE_COMMAND} -E echo "cineb barrier ${NEBBARRIER}, string barrier ${STRINGBARRIER}")
# The windows are the measured barriers plus/minus 0.05 kcal/mol (report 39
# section 8.2: CI-NEB 6.0825, string 6.0702 on this reaction), so a regression of
# the 0.1 kcal/mol class that report 36 section 7.4 used as the cross
# validation cannot pass any more (report 38 L-8).
if(NEBBARRIER LESS 6.03 OR NEBBARRIER GREATER 6.13)
  message(FATAL_ERROR "the CI-NEB barrier ${NEBBARRIER} is outside the expected window")
endif()
if(STRINGBARRIER LESS 6.02 OR STRINGBARRIER GREATER 6.12)
  message(FATAL_ERROR "the string barrier ${STRINGBARRIER} is outside the expected window")
endif()
]=])
add_test("xtb/landscape-path-string"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-NH3}
  -DPRODUCT=${LANDSCAPE-NH3-DOWN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-string
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_string.cmake")

# The AutoNEB resource bounds are hard limits: a request above `max_paths` and a
# coarse path above the request are rejected, never silently truncated.
add_test("xtb/landscape-path-autoneb-max-paths"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method autoneb --lts-images 14 --lts-product ${LANDSCAPE-NH3-DOWN}"
  "-DPATTERN=exceeds the hard AutoNEB limit max_paths"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-autoneb-nstart"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method autoneb --lts-autoneb-nstart 12 --lts-product ${LANDSCAPE-NH3-DOWN}"
  "-DPATTERN=exceeds the requested number of images"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")
add_test("xtb/landscape-path-string-ds-too-large"
  ${CMAKE_COMMAND} -DEXE=${XTB-EXE} -DINPUT=${LANDSCAPE-NH3}
  "-DARGS=--gfn 2 --lts --lts-method string --lts-string-ds 5.0 --lts-product ${LANDSCAPE-NH3-DOWN}"
  "-DPATTERN=is not smaller than the distance between the endpoints"
  -DRUNDIR=${LANDSCAPE-PATH-DIR}
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_error.cmake")

# The image bound is a hard limit for an **adopted** path as well: a restart
# file with more frames than `max_paths` is rejected instead of being adopted
# verbatim (report 38 L-3).  The multi frame file is built by this test from
# the single frame input, so it does not depend on the path file of another
# test having been written.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_autoneb_adopt.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
file(READ "${INPUT}" frame)
set(ADOPTED "${RUNDIR}/adopted_multi.xyz")
file(WRITE "${ADOPTED}" "")
foreach(i RANGE 1 18)
  file(APPEND "${ADOPTED}" "${frame}")
  file(APPEND "${ADOPTED}" "\n")
endforeach()
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method autoneb
          --lts-product "${PRODUCT}" --lts-autoneb-restart "${ADOPTED}"
          --lts-autoneb-max-paths 10 --lts-max-steps 100 --norestart
          --namespace pA
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(status EQUAL 0)
  message(FATAL_ERROR "an oversized adopted path was accepted\n${output}")
endif()
if(NOT output MATCHES "more than the hard limit")
  message(FATAL_ERROR "the reported failure is not the image bound\n${output}")
endif()
]=])
add_test("xtb/landscape-path-autoneb-adopt-limit"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-NH3}
  -DPRODUCT=${LANDSCAPE-NH3-DOWN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-autoneb-adopt
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_autoneb_adopt.cmake")

# A run that stops at the AutoNEB insertion depth cap has to report the cap in
# the result message - and therefore in `xtbts.log` - instead of a bare
# "converged": the band of the last stage did converge, but the requested path
# was not built (report 38 L-2).  Before the fix the log said "converged"
# while the path held 6 of 9 images; the propagation had no automatic coverage
# at all (the branch was only exercised by hand, R2-L6).
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_autoneb_cap.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
file(REMOVE "${RUNDIR}/pC.xtbts.log")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --lts --lts-method autoneb
          --lts-product "${PRODUCT}" --lts-autoneb-max-depth 1
          --lts-max-steps 400 --norestart --namespace pC
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "the capped AutoNEB run terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "autoneb: budget limit reached")
  message(FATAL_ERROR "the AutoNEB insertion cap was not reached\n${output}")
endif()
if(NOT output MATCHES "landscape task terminated: stopped at the insertion depth limit max_depth = 1")
  message(FATAL_ERROR "the cap did not reach the result message\n${output}")
endif()
if(NOT EXISTS "${RUNDIR}/pC.xtbts.log")
  message(FATAL_ERROR "xtbts.log was not written")
endif()
file(READ "${RUNDIR}/pC.xtbts.log" log)
if(NOT log MATCHES "termination: stopped at the insertion depth limit max_depth = 1")
  message(FATAL_ERROR "the cap did not reach xtbts.log\n${log}")
endif()
if(log MATCHES "termination: converged")
  message(FATAL_ERROR "xtbts.log claims convergence for a capped run\n${log}")
endif()
]=])
add_test("xtb/landscape-path-autoneb-depth-limit"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-NH3}
  -DPRODUCT=${LANDSCAPE-NH3-DOWN}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-autoneb-cap
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_autoneb_cap.cmake")

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
  "xtb/landscape-opt-hessian"
  "xtb/landscape-scf-failure"
  "xtb/landscape-engine-missing"
  "xtb/landscape-engine-unknown"
  "xtb/landscape-level-missing"
  "xtb/landscape-level-unknown"
  "xtb/landscape-hessian-unknown"
  "xtb/landscape-scan-cli"
  "xtb/landscape-scan-failed-point"
  "xtb/landscape-scan-coord-unknown"
  "xtb/landscape-scan-nstep-missing"
  "xtb/landscape-scan-atom-range"
  "xtb/landscape-vib-odlr"
  "xtb/landscape-vib-hessian-missing-file"
  "xtb/landscape-vib-hessian-unknown"
  "xtb/landscape-vib-temperature-invalid"
  "xtb/landscape-vib-imag-cutoff-invalid"
  PROPERTIES
  ENVIRONMENT XTBPATH=${PROJECT_SOURCE_DIR}
)

# The scan suite runs GFN2 single points; with the default thread count the
# 340x OpenMP anti-scaling of AGENTS.md section 6.8 turns it into a 20 s test
# (0.13 s with one thread), and one thread also removes the last bit of thread
# dependence from the scan assertions.
set_tests_properties(
  "${PROJECT_NAME}/landscape-scan"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"
)

# The frequency suite builds numerical Hessians (6N GFN2 single points each);
# one thread keeps the 340x OpenMP anti-scaling of AGENTS.md section 6.8 out
# of the picture and makes the Hessians reproducible.
set_tests_properties(
  "${PROJECT_NAME}/landscape-vib"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"
)

# The end-to-end suite runs the opt -> freq -> thermo chain and a TS -> IRC
# run on real GFN2 calculations; one thread is required for the bitwise
# reproducibility of the engine (AGENTS.md section 6.1) and for the 340x
# OpenMP anti-scaling of many small single points (AGENTS.md section 6.8).
set_tests_properties(
  "${PROJECT_NAME}/landscape-e2e"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"
)

# The same holds for every landscape CLI check that runs the engine (PLAN
# appendix A: scan/Hessian benchmarks and tests always use one thread); the
# error branches and the unconverged-SCC probe abort before/without a real
# calculation and keep the plain environment.
set_tests_properties(
  "xtb/landscape-opt"
  "xtb/landscape-opt-namespace"
  "xtb/landscape-opt-energy"
  "xtb/landscape-opt-acc"
  "xtb/landscape-opt-hessian"
  "xtb/landscape-scan-cli"
  "xtb/landscape-vib-cli"
  "xtb/landscape-vib-etemp"
  "xtb/landscape-vib-namespace"
  "xtb/landscape-scan-max-steps"
  "xtb/landscape-scan-hessian"
  "xtb/landscape-ts-prfo"
  "xtb/landscape-ts-etemp"
  "xtb/landscape-ts-dimer"
  "xtb/landscape-ts-minimum"
  "xtb/landscape-ts-escape"
  "xtb/landscape-ts-namespace"
  "xtb/landscape-path-cli"
  "xtb/landscape-path-product-single-ended"
  "xtb/landscape-path-autoneb"
  "xtb/landscape-path-autoneb-depth-limit"
  "xtb/landscape-path-string"
  "xtb/landscape-irc-cli"
  "xtb/landscape-irc-knobs"
  "xtb/landscape-irc-swap"
  "xtb/landscape-irc-termination"
  "xtb/landscape-irc-pc"
  "xtb/landscape-irc-minimum"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"
)

# The failed scan points evaluate SCCs at strongly stretched geometries; with
# the default thread count the 340x OpenMP anti-scaling of AGENTS.md section
# 6.8 turns a 0.2 s run into 30 s.
set_tests_properties(
  "xtb/landscape-scan-failed-point"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"
)

# ---------------------------------------------------------------------------
# M7: `--ljson` and the end-to-end validation script
# ---------------------------------------------------------------------------
#
# `test/unit/landscape_e2e_check.py` implements the layered validation of
# PLAN section 9.8 and the machine readable checks of `--ljson`: the JSON
# document is parsed with the standard library, every counter is compared
# against the number the task printed on stdout, a second run has to be byte
# identical and `--namespace` has to prefix the file name.  The checks need a
# JSON parser, so they are driven by the Python interpreter instead of a
# `cmake -P` script.
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(LANDSCAPE-E2E-PY "${CMAKE_CURRENT_SOURCE_DIR}/landscape_e2e_check.py")
set(LANDSCAPE-E2E-XTB "${XTB-EXE}")
# the tester executable of this directory (a generator expression would not
# be expanded inside the quoted -DARGS value)
set(LANDSCAPE-E2E-TESTER "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-tester")

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake" [=[
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${PYTHON}" "${SCRIPT}" ${ARGS}
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "landscape_e2e_check.py failed with status ${status}\n${output}")
endif()
]=])

# One `--ljson` check per landscape task reachable from the command line.
# The `sp` task has no run type of its own (it is API only), so it is covered
# by the unit test `landscape-e2e` case `sp-ljson`.
foreach(task IN ITEMS opt scan scan2d vib ts irc)
  if(task STREQUAL "ts" OR task STREQUAL "irc")
    set(e2e-input "${LANDSCAPE-HCN}")
  else()
    set(e2e-input "${LANDSCAPE-H2O}")
  endif()
  add_test("xtb/landscape-ljson-${task}"
    ${CMAKE_COMMAND}
    -DPYTHON=${Python3_EXECUTABLE}
    -DSCRIPT=${LANDSCAPE-E2E-PY}
    "-DARGS=ljson;${LANDSCAPE-E2E-XTB};${e2e-input};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-ljson-${task};${task}"
    -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-ljson-${task}
    -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")
endforeach()

# `--ljson` is an output switch, not a run type: without one of `--lopt`,
# `--lscan`, `--lvib`, `--lts`, `--lirc` it writes nothing, which used to be a
# silent no-op (finding L-9 of `50-m7-independent-review.md`).  The check pins
# both halves of the contract: the no-op is reported on stderr, no document is
# written, and the run itself still exits 0 because the request is not an error.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ljson_norun.cmake" [=[
file(REMOVE_RECURSE "${RUNDIR}")
file(MAKE_DIRECTORY "${RUNDIR}")
execute_process(
  COMMAND "${EXE}" "${INPUT}" --gfn 2 --ljson
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE status
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --ljson terminated with status ${status}\n${output}")
endif()
if(NOT output MATCHES "writes nothing without a landscape run type")
  message(FATAL_ERROR "the --ljson no-op was not reported\n${output}")
endif()
file(GLOB documents "${RUNDIR}/landscape_*.json")
if(documents)
  message(FATAL_ERROR "--ljson wrote a document without a landscape run type: ${documents}")
endif()
]=])
add_test("xtb/landscape-ljson-no-runtype"
  ${CMAKE_COMMAND}
  -DEXE=${XTB-EXE}
  -DINPUT=${LANDSCAPE-H2O}
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-cli-ljson-no-runtype
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_ljson_norun.cmake")

# The product endpoint of the HCN/HNC band searches (same atom order as the
# reactant, HNC on the H-C-N line).  A distinct variable name: `LANDSCAPE-HNC`
# above is the linear-HNC input of the transition state tests.
set(LANDSCAPE-HNC-PRODUCT "${CMAKE_CURRENT_BINARY_DIR}/landscape_hnc_product.xyz")
file(WRITE "${LANDSCAPE-HNC-PRODUCT}"
  "3\nHNC product\n"
  "H  1.0000000  0.0000000  0.0000000\n"
  "C -1.1700000  0.0000000  0.0000000\n"
  "N  0.0000000  0.0000000  0.0000000\n")

# `--ljson` must produce a valid document for every task method: the eight `ts`
# methods (four of which are the band searches with their own code path) and the
# four `irc` methods.  The assertion is the document (task name, method
# identifier, parseability), not convergence.
add_test("xtb/landscape-e2e-ljson-methods"
  ${CMAKE_COMMAND}
  -DPYTHON=${Python3_EXECUTABLE}
  -DSCRIPT=${LANDSCAPE-E2E-PY}
  "-DARGS=ljson-methods;${LANDSCAPE-E2E-XTB};${LANDSCAPE-HCN};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-ljson-methods;${LANDSCAPE-HNC-PRODUCT}"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-ljson-methods
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")

# The sampling point of the `ts` evaluation counter (PLAN section 12.11): the
# counter of a run is the complete run, so it equals the engine's own report,
# and `--lts-no-verify` removes exactly whole 6N confirmation Hessians.
add_test("xtb/landscape-e2e-ts-counters"
  ${CMAKE_COMMAND}
  -DPYTHON=${Python3_EXECUTABLE}
  -DSCRIPT=${LANDSCAPE-E2E-PY}
  "-DARGS=ts-counters;${LANDSCAPE-E2E-XTB};${LANDSCAPE-HCN};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-ts-counters"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-ts-counters
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")

# The point bookkeeping of a scan (`n_points`/`n_valid`/`n_fail`/
# `n_unconverged`) against the frames the task writes, converged and not.
add_test("xtb/landscape-e2e-scan-counters"
  ${CMAKE_COMMAND}
  -DPYTHON=${Python3_EXECUTABLE}
  -DSCRIPT=${LANDSCAPE-E2E-PY}
  "-DARGS=scan-counters;${LANDSCAPE-E2E-XTB};${LANDSCAPE-H2O};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-scan-counters"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-scan-counters
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")

# L3: the chain `opt -> hess -> freq -> thermo`, compared against `--hess`.
add_test("xtb/landscape-e2e-chain"
  ${CMAKE_COMMAND}
  -DPYTHON=${Python3_EXECUTABLE}
  -DSCRIPT=${LANDSCAPE-E2E-PY}
  "-DARGS=chain;${LANDSCAPE-E2E-XTB};${LANDSCAPE-H2O};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-chain"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-chain
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")

# The failure path of the chain: step 1 (`--lopt`) succeeds, step 2 (`--lvib`
# with a missing Hessian file) is misconfigured, and the runner must abort
# instead of continuing with a step that failed.
add_test("xtb/landscape-e2e-chain-failure"
  ${CMAKE_COMMAND}
  -DPYTHON=${Python3_EXECUTABLE}
  -DSCRIPT=${LANDSCAPE-E2E-PY}
  "-DARGS=chain-failure;${LANDSCAPE-E2E-XTB};${LANDSCAPE-H2O};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-chain-failure"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-chain-failure
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")

# L1 + L2 + L3 in one structured report; the second L3 leg (the `ts -> irc`
# chain) needs the transition state input, which is passed as a sixth argument.
add_test("xtb/landscape-e2e-layers"
  ${CMAKE_COMMAND}
  -DPYTHON=${Python3_EXECUTABLE}
  -DSCRIPT=${LANDSCAPE-E2E-PY}
  "-DARGS=layers;${LANDSCAPE-E2E-XTB};${LANDSCAPE-E2E-TESTER};${LANDSCAPE-H2O};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-layers;${LANDSCAPE-HCN}"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-layers
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")

# The MAPLE comparison: topology only, and an explicit record of whether MAPLE
# was executed (it is not, its fixtures use machine learning potentials).
add_test("xtb/landscape-e2e-maple"
  ${CMAKE_COMMAND}
  -DPYTHON=${Python3_EXECUTABLE}
  -DSCRIPT=${LANDSCAPE-E2E-PY}
  "-DARGS=maple;${LANDSCAPE-E2E-XTB};${LANDSCAPE-HCN};${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-maple"
  -DRUNDIR=${CMAKE_CURRENT_BINARY_DIR}/landscape-e2e-maple
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_e2e_py.cmake")

# Every new M7 CLI check runs real GFN2 calculations; one thread keeps the
# 340x OpenMP anti-scaling of many small single points out of the picture
# (AGENTS.md section 6.8).
set_tests_properties(
  "xtb/landscape-ljson-opt"
  "xtb/landscape-ljson-no-runtype"
  "xtb/landscape-ljson-scan"
  "xtb/landscape-ljson-scan2d"
  "xtb/landscape-ljson-vib"
  "xtb/landscape-ljson-ts"
  "xtb/landscape-ljson-irc"
  "xtb/landscape-e2e-ljson-methods"
  "xtb/landscape-e2e-ts-counters"
  "xtb/landscape-e2e-scan-counters"
  "xtb/landscape-e2e-chain"
  "xtb/landscape-e2e-chain-failure"
  "xtb/landscape-e2e-layers"
  "xtb/landscape-e2e-maple"
  PROPERTIES
  ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"
)
