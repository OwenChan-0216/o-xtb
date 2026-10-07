# Guard for the historical `libxtb.*` compatibility links.
#
# `CMakeLists.txt` installs `libxtb.a` (and, under `WITH_OBJECT`, `libxtb.so`)
# as symlinks to the current `liboxtb.*` artifact, so consumers that resolve
# the library by **file name** (the `xtb-python` wheel loads `libxtb.so`,
# recipes link `libxtb.a`) keep working without a rebuild.  Those links are a
# transition aid and nothing in the tree exercises them: without this check a
# removed block, or a renamed target, would leave the install tree silently
# without the drop-in links.
#
# The check runs the **real install rules** into a scratch prefix
# (`cmake --install`, rules only - no rebuild and no reconfigure) and asserts
# that each link exists, is a symlink, resolves to an existing file and points
# at the expected `liboxtb.*` name.  Deleting the compatibility block from the
# top-level `CMakeLists.txt` (followed by a reconfigure, so the generated
# install script loses it) turns this test red.
#
# Inputs (passed with -D on the add_test command line):
#   BUILD_DIR       the build tree to install from
#   INSTALL_LIBDIR  the install libdir (`lib` on this machine)
#   LIB_NAME        the current library base name (`oxtb`, from XTB_LIB_NAME)
#   WITH_OBJECT     ON when the shared library is built and `libxtb.so` exists
#   CONFIG          the build configuration to pass to `cmake --install`
#   RUNDIR          scratch directory (removed and rebuilt on every run)

if(NOT BUILD_DIR OR NOT INSTALL_LIBDIR OR NOT LIB_NAME OR NOT RUNDIR)
  message(FATAL_ERROR "missing input: BUILD_DIR/INSTALL_LIBDIR/LIB_NAME/RUNDIR")
endif()

file(REMOVE_RECURSE "${RUNDIR}")
file(MAKE_DIRECTORY "${RUNDIR}")
set(_prefix "${RUNDIR}/prefix")

set(_config_args)
if(CONFIG)
  list(APPEND _config_args --config "${CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${BUILD_DIR}" --prefix "${_prefix}" ${_config_args}
  WORKING_DIRECTORY "${RUNDIR}"
  RESULT_VARIABLE _status
  OUTPUT_VARIABLE _output
  ERROR_VARIABLE _output
)
if(NOT _status EQUAL 0)
  message(FATAL_ERROR "cmake --install failed (status ${_status}):\n${_output}")
endif()

set(_libdir "${_prefix}/${INSTALL_LIBDIR}")
set(_static "lib${LIB_NAME}.a")
if(NOT EXISTS "${_libdir}/${_static}")
  message(FATAL_ERROR
    "the install tree has no ${_static} in ${_libdir}:\n${_output}")
endif()

set(_links "libxtb.a=${_static}")
if(WITH_OBJECT)
  list(APPEND _links "libxtb.so=lib${LIB_NAME}.so")
endif()

set(_fail "")
foreach(_pair IN LISTS _links)
  string(REPLACE "=" ";" _parts "${_pair}")
  list(GET _parts 0 _link)
  list(GET _parts 1 _expected)
  set(_path "${_libdir}/${_link}")
  if(NOT IS_SYMLINK "${_path}")
    string(APPEND _fail "\n  ${_link}: not a symlink at ${_path}")
    continue()
  endif()
  if(NOT EXISTS "${_path}")
    string(APPEND _fail "\n  ${_link}: dangling symlink to ${_expected}")
    continue()
  endif()
  file(READ_SYMLINK "${_path}" _actual)
  if(NOT _actual STREQUAL "${_expected}")
    string(APPEND _fail
      "\n  ${_link}: points at '${_actual}', expected '${_expected}'")
    continue()
  endif()
  message(STATUS "compatibility link ok: ${_link} -> ${_actual}")
endforeach()

if(_fail)
  message(FATAL_ERROR "compatibility link check failed:${_fail}")
endif()
message(STATUS "compatibility link check passed")
