include(FetchContent)

FetchContent_Declare(
  Catch2
  GIT_REPOSITORY https://github.com/catchorg/Catch2.git
  GIT_TAG v3.5.4
)
FetchContent_MakeAvailable(Catch2)

function(apm44_add_test name)
  add_executable(${name} ${ARGN})
  target_link_libraries(${name} PRIVATE apm44_shared Catch2::Catch2WithMain)
  target_include_directories(${name} PRIVATE
    ${CMAKE_SOURCE_DIR}/BridgeDaemon/src
    ${CMAKE_SOURCE_DIR}/Shared/include
  )
  add_test(NAME ${name} COMMAND ${name})
endfunction()

apm44_add_test(test_audio_formats test_audio_formats.cpp)
apm44_add_test(test_device_enumerator test_device_enumerator.cpp)
apm44_add_test(test_planar_ring_buffer test_planar_ring_buffer.cpp)
apm44_add_test(test_audio_converter_src test_audio_converter_src.cpp)
apm44_add_test(test_libsamplerate_smoke test_libsamplerate_smoke.cpp)
apm44_add_test(test_drift_controller test_drift_controller.cpp)
apm44_add_test(test_lib_samplerate_src test_lib_samplerate_src.cpp)
apm44_add_test(test_soak_offline test_soak_offline.cpp)

target_link_libraries(test_libsamplerate_smoke PRIVATE samplerate::samplerate)
target_link_libraries(test_lib_samplerate_src PRIVATE samplerate::samplerate)

target_sources(test_device_enumerator PRIVATE
  ${CMAKE_SOURCE_DIR}/BridgeDaemon/src/hal/DeviceEnumerator.cpp
)
target_sources(test_audio_converter_src PRIVATE
  ${CMAKE_SOURCE_DIR}/BridgeDaemon/src/engine/AudioConverterSrc.cpp
)
target_sources(test_lib_samplerate_src PRIVATE
  ${CMAKE_SOURCE_DIR}/BridgeDaemon/src/engine/LibSamplerateSrc.cpp
)
target_sources(test_soak_offline PRIVATE
  ${CMAKE_SOURCE_DIR}/BridgeDaemon/src/tools/SoakHarness.cpp
  ${CMAKE_SOURCE_DIR}/BridgeDaemon/src/engine/LibSamplerateSrc.cpp
)

target_link_libraries(test_device_enumerator PRIVATE
  "-framework CoreAudio"
  "-framework AudioToolbox"
  "-framework CoreFoundation"
)
target_link_libraries(test_audio_converter_src PRIVATE
  "-framework CoreAudio"
  "-framework AudioToolbox"
)
target_link_libraries(test_lib_samplerate_src PRIVATE samplerate::samplerate)
target_link_libraries(test_soak_offline PRIVATE samplerate::samplerate)
