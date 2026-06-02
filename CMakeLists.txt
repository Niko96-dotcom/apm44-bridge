cmake_minimum_required(VERSION 3.28)

project(APM44Bridge VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "Allow pinned third-party projects with older CMake policies")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(APPLE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS version")
endif()

set(APM44_GIT_SHA "nogit")
find_package(Git QUIET)
if(Git_FOUND)
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" rev-parse --short=12 HEAD
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    OUTPUT_VARIABLE APM44_GIT_SHA_OUT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  if(APM44_GIT_SHA_OUT)
    set(APM44_GIT_SHA "${APM44_GIT_SHA_OUT}")
  endif()
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" diff --quiet --ignore-submodules HEAD
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    RESULT_VARIABLE APM44_GIT_DIRTY
    OUTPUT_QUIET
    ERROR_QUIET
  )
  if(NOT APM44_GIT_DIRTY EQUAL 0)
    string(APPEND APM44_GIT_SHA "-dirty")
  endif()
endif()
set(APM44_BUILD_ID "${PROJECT_VERSION}+${APM44_GIT_SHA}" CACHE STRING "APM44 build fingerprint")
message(STATUS "APM44 build id: ${APM44_BUILD_ID}")

enable_testing()

include(cmake/Libsamplerate.cmake)
include(cmake/LibASPL.cmake)

add_subdirectory(Shared)
add_subdirectory(BridgeDaemon)
if(APPLE)
  add_subdirectory(Driver)
endif()
add_subdirectory(tests)
