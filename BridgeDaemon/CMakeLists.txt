add_executable(apm44-bridge
  src/main.cpp
  src/CliOptions.cpp
  src/hal/DeviceEnumerator.cpp
  src/hal/FormatNegotiator.cpp
  src/engine/AudioConverterSrc.cpp
  src/engine/LibSamplerateSrc.cpp
  src/engine/IoProcHandlers.cpp
  src/engine/BridgeEngine.cpp
  src/engine/BridgeMetrics.cpp
  src/engine/VirtualDeviceFeed.cpp
)

target_include_directories(apm44-bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(apm44-bridge
  PRIVATE
    apm44_shared
    samplerate::samplerate
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework CoreFoundation"
)

set_target_properties(apm44-bridge PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/BridgeDaemon"
)

add_executable(apm44-soak
  src/tools/apm44_soak_main.cpp
  src/tools/SoakHarness.cpp
  src/engine/LibSamplerateSrc.cpp
)

target_include_directories(apm44-soak PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(apm44-soak
  PRIVATE
    apm44_shared
    samplerate::samplerate
)

set_target_properties(apm44-soak PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/BridgeDaemon"
)
