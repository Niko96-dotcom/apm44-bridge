# Pinned libASPL (MIT) — see third_party/README.md
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_DOCUMENTATION OFF CACHE BOOL "" FORCE)

add_subdirectory(
  ${CMAKE_SOURCE_DIR}/third_party/libASPL
  ${CMAKE_BINARY_DIR}/libASPL-build
  EXCLUDE_FROM_ALL
)

add_library(aspl::libASPL ALIAS libASPL)
