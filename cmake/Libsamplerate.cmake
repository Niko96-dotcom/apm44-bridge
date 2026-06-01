# Pinned libsamplerate 0.2.2 — static library for apm44-bridge and tests.

set(_apm44_samplerate_dir "${CMAKE_SOURCE_DIR}/third_party/libsamplerate")

if(NOT EXISTS "${_apm44_samplerate_dir}/CMakeLists.txt")
  include(FetchContent)
  FetchContent_Declare(
    libsamplerate
    GIT_REPOSITORY https://github.com/libsndfile/libsamplerate.git
    GIT_TAG 0.2.2
  )
  FetchContent_Populate(libsamplerate)
  set(_apm44_samplerate_dir "${libsamplerate_SOURCE_DIR}")
endif()

set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(LIBSAMPLERATE_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LIBSAMPLERATE_INSTALL OFF CACHE BOOL "" FORCE)

add_subdirectory("${_apm44_samplerate_dir}" "${CMAKE_BINARY_DIR}/third_party/libsamplerate" EXCLUDE_FROM_ALL)

if(TARGET samplerate)
  add_library(samplerate::samplerate ALIAS samplerate)
endif()
