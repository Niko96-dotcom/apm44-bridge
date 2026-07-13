#pragma once

namespace apm44 {

using ParentDeathCallback = void (*)();

// Blocks until the read side observes EOF (all parent writers closed).
// EINTR is retried; other read errors fail closed and are treated as loss
// of the parent channel.
bool WaitForParentChannelClose(int fileDescriptor) noexcept;

// The detached watcher owns no heap-backed runtime state after it starts.
// It is intended for a pipe inherited as the helper's standard input.
void StartParentDeathWatch(int fileDescriptor, ParentDeathCallback callback);

}  // namespace apm44
