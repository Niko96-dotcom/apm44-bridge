#pragma once

// Real-time (IOProc) constraints for APM44 Bridge — ENG-05 / Phase 1 CONTEXT.
//
// Audio device IO callbacks MUST NOT:
//   - malloc, free, or realloc
//   - acquire mutexes, locks, or condition variables
//   - log (spdlog, NSLog, fprintf, std::cerr, etc.)
//   - perform file I/O or network I/O
//   - enumerate devices or mutate UI
//   - invoke Swift / Obj-C messaging on hot paths
//
// Setup (device discovery, format negotiation, converter creation, buffer
// allocation) belongs on the main thread before AudioDeviceStart.
