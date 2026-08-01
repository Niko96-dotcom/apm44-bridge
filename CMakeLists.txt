cmake_minimum_required(VERSION 3.28)

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" APM44_VERSION LIMIT_COUNT 1)
if(NOT APM44_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  message(FATAL_ERROR "VERSION must contain one semantic version (found '${APM44_VERSION}')")
endif()
project(APM44Bridge VERSION "${APM44_VERSION}" LANGUAGES CXX)

set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "Allow pinned third-party projects with older CMake policies")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(APM44_SANITIZER "none" CACHE STRING "Native sanitizer: none, address, or thread")
set_property(CACHE APM44_SANITIZER PROPERTY STRINGS none address thread)
if(NOT APM44_SANITIZER STREQUAL "none")
  if(NOT CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang")
    message(FATAL_ERROR "APM44 sanitizers require Clang")
  endif()
  add_compile_options(-fno-omit-frame-pointer)
  if(APM44_SANITIZER STREQUAL "address")
    add_compile_options(-fsanitize=address,undefined)
    add_link_options(-fsanitize=address,undefined)
  elseif(APM44_SANITIZER STREQUAL "thread")
    add_compile_options(-fsanitize=thread)
    add_link_options(-fsanitize=thread)
  else()
    message(FATAL_ERROR "Unknown APM44_SANITIZER='${APM44_SANITIZER}'")
  endif()
  message(STATUS "APM44 sanitizer: ${APM44_SANITIZER}")
endif()

if(APPLE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS version")
  if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING
        "Release architectures supported by APM44 Bridge" FORCE)
  endif()
endif()

set(APM44_GIT_SHA "nogit")
find_package(Git QUIET)
if(Git_FOUND)
  # The signed Sparkle feed is release metadata generated after the binaries
  # are built. Exclude that file from the source fingerprint so committing a
  # freshly signed appcast does not make an otherwise identical payload look
  # stale or mismatched at install time.
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" rev-list -n 1 HEAD -- . ":(exclude)docs/appcast.xml"
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
set(APM44_BUILD_ID "${PROJECT_VERSION}+${APM44_GIT_SHA}" CACHE STRING "APM44 build fingerprint" FORCE)
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
