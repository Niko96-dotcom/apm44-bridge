add_library(apm44_shared STATIC
  src/AudioFormats.cpp
  src/PlanarRingBuffer.cpp
  src/DriftController.cpp
  src/MmapShmRing.cpp
)

target_include_directories(apm44_shared
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_definitions(apm44_shared
  PUBLIC
    APM44_VERSION_STRING="${PROJECT_VERSION}"
    APM44_BUILD_ID="${APM44_BUILD_ID}"
)

target_link_libraries(apm44_shared
  PUBLIC
    "-framework CoreAudio"
    "-framework AudioToolbox"
)
