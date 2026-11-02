# Builds VLC 3.0.21's patched WASAPI output module with MinGW (GNU C) and stages the package.
# Run by autobuild from <root>/stage:  cmake -P ../build.cmake
# The compile command and flags are those of the viewer's former indra/media_plugins/libvlc/CMakeLists.txt.
cmake_minimum_required(VERSION 3.24)
set(root "${CMAKE_CURRENT_LIST_DIR}")
set(stage "${root}/stage")
# autobuild installs dependencies under the package's build_directory (stage/packages);
# an explicit --install-dir may put them at <root>/packages instead.
set(packages "${stage}/packages")
if (NOT EXISTS "${packages}/include/vlc/plugins/vlc_common.h" AND EXISTS "${root}/packages/include/vlc/plugins/vlc_common.h")
  set(packages "${root}/packages")
endif ()
message(STATUS "Dependencies (vlc-bin) under ${packages}")

# Mirror of the viewer's AUTOBUILD_INSTALL_DIR / VLCCORE_LIBRARY.
set(AUTOBUILD_INSTALL_DIR "${packages}")
if (NOT EXISTS "${AUTOBUILD_INSTALL_DIR}/include/vlc/plugins/vlc_common.h")
  message(FATAL_ERROR "vlc-bin is not installed under ${packages} (nor ${root}/packages); run: autobuild install -A 64")
endif ()
find_library(VLCCORE_LIBRARY NAMES libvlccore.lib PATHS "${packages}/lib/release" REQUIRED NO_DEFAULT_PATH)

# Deliberately no fallback to any other compiler: the module is GNU C and must be built by MinGW.
find_program(VLC_MODULE_CC NAMES x86_64-w64-mingw32-gcc NO_CACHE)
if (NOT VLC_MODULE_CC)
  message(FATAL_ERROR "x86_64-w64-mingw32-gcc not found on PATH (the CI workflow installs a pinned llvm-mingw)")
endif ()
get_filename_component(mingw_bin "${VLC_MODULE_CC}" DIRECTORY)
find_program(MINGW_OBJDUMP NAMES x86_64-w64-mingw32-objdump objdump HINTS "${mingw_bin}" NO_DEFAULT_PATH REQUIRED NO_CACHE)
execute_process(COMMAND "${VLC_MODULE_CC}" --version OUTPUT_VARIABLE compiler_version
  COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${VLC_MODULE_CC}" -dumpmachine OUTPUT_VARIABLE compiler_machine
  OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
# GCC-based MinGW reports x86_64-w64-mingw32; llvm-mingw's clang reports the same target as x86_64-w64-windows-gnu.
if (NOT compiler_machine MATCHES "^x86_64-w64-(mingw32|windows-gnu)")
  message(FATAL_ERROR "Compiler targets '${compiler_machine}', expected x86_64-w64-mingw32 or x86_64-w64-windows-gnu")
endif ()
message(STATUS "Compiler: ${VLC_MODULE_CC}\n${compiler_version}")

file(REMOVE_RECURSE "${stage}/lib" "${stage}/share" "${stage}/LICENSES")
file(MAKE_DIRECTORY "${stage}/lib/release" "${stage}/LICENSES")
file(COPY "${root}/VERSION.txt" DESTINATION "${stage}")

# Hash-checked upstream sources and the patch (unchanged from the viewer's prepare_speakerfill.cmake).
set(SPEAKERFILL_SOURCE_DIR "${stage}/share/vlc-speakerfill/source")
include("${root}/prepare_speakerfill.cmake")
file(COPY "${root}/prepare_speakerfill.cmake" DESTINATION "${stage}/share/vlc-speakerfill")

# VLC's licence text: wasapi.c is LGPL-2.1-or-later (COPYING.LIB in the 3.0.21 tree).
file(DOWNLOAD "https://raw.githubusercontent.com/videolan/vlc/3.0.21/COPYING.LIB"
  "${stage}/LICENSES/vlc-speakerfill.txt"
  EXPECTED_HASH SHA256=dc626520dcd53a22f727af3ee42c770e56c97a64fe3adb063799d8ab032fe551 TLS_VERIFY ON)

set(SPEAKERFILL_OUTPUT "${stage}/lib/release/libspeakerfill_output_plugin.dll")
execute_process(COMMAND "${VLC_MODULE_CC}" -shared -std=gnu11 -O2 -g -DHAVE_ATTRIBUTE_PACKED -D__PLUGIN__ -DMODULE_STRING="speakerfill_output"
    -I "${AUTOBUILD_INSTALL_DIR}/include/vlc/plugins" -I "${SPEAKERFILL_SOURCE_DIR}"
    "${SPEAKERFILL_SOURCE_DIR}/speakerfill_output.c" "${VLCCORE_LIBRARY}"
    -lole32 -luuid -lksuser -lwinmm -lws2_32 -o "${SPEAKERFILL_OUTPUT}"
  COMMAND_ERROR_IS_FATAL ANY)

# Smoke test: a VLC 3 plugin must export its module entry points and link libvlccore.
execute_process(COMMAND "${MINGW_OBJDUMP}" -p "${SPEAKERFILL_OUTPUT}"
  OUTPUT_VARIABLE dump COMMAND_ERROR_IS_FATAL ANY)
foreach (symbol vlc_entry__3_0_0f vlc_entry_license__3_0_0f vlc_entry_copyright__3_0_0f)
  if (NOT dump MATCHES "${symbol}")
    message(FATAL_ERROR "Smoke test: ${symbol} is not exported by ${SPEAKERFILL_OUTPUT}")
  endif ()
endforeach ()
if (NOT dump MATCHES "libvlccore\.dll")
  message(FATAL_ERROR "Smoke test: libvlccore.dll is not imported")
endif ()
message(STATUS "Smoke test passed: VLC module entry points exported, libvlccore.dll imported")

file(READ "${root}/VERSION.txt" package_version)
string(STRIP "${package_version}" package_version)
file(WRITE "${stage}/share/vlc-speakerfill/build-info.txt"
  "package: vlc-speakerfill ${package_version}\nvlc: 3.0.21\ncompiler:\n${compiler_version}\n")
