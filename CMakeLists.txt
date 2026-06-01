cmake_minimum_required(VERSION 3.28)

project(APM44Bridge VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(APPLE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS version")
endif()

enable_testing()

add_subdirectory(Shared)
add_subdirectory(BridgeDaemon)
add_subdirectory(tests)
