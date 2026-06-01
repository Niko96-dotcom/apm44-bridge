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

target_link_libraries(apm44_shared
  PUBLIC
    "-framework CoreAudio"
    "-framework AudioToolbox"
)
