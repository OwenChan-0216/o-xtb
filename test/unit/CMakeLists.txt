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
if(NOT status EQUAL 0)
  message(FATAL_ERROR "xtb --lscan --lscan-max-steps 0 failed with status ${status}\n${output}")
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

# The same holds for every landscape CLI check that runs the engine (PLAN
# appendix A: scan/Hessian benchmarks and tests always use one thread); the
# error branches and the unconverged-SCC probe abort before/without a real
# calculation and keep the plain environment.
set_tests_properties(
  "xtb/landscape-opt"
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
