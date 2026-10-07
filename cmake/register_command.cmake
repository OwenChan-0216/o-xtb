# This file is part of xtb.
#
# Copyright (C) 2026 xtb contributors
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
#
# SPDX-Identifier: LGPL-3.0-or-later
#
# Create or refresh the symlink that registers the built command line program
# in the user's own binary directory.  This is CMake *script* mode, invoked from
# the top level CMakeLists.txt as a post-build step of the executable when
# -DXTB_REGISTER_COMMAND=ON; it is part of the build, so it writes only when the
# user asked for it.
#
# Required input:
#   REGISTER_TARGET  absolute path of the built executable
#
# The link is named after the executable, so the same script serves the
# `xtb` and the renamed `oxtb` tree.

if(NOT DEFINED REGISTER_TARGET)
  message(FATAL_ERROR "REGISTER_TARGET was not set")
endif()

get_filename_component(register_name "${REGISTER_TARGET}" NAME)
set(register_dir "$ENV{HOME}/.local/bin")

# An existing link is replaced; the build directory is the link target on
# purpose, so that a rebuilt executable is picked up without reinstalling.
file(MAKE_DIRECTORY "${register_dir}")
file(CREATE_LINK "${REGISTER_TARGET}" "${register_dir}/${register_name}" SYMBOLIC)

message(STATUS "registered ${register_name} -> ${REGISTER_TARGET}")
