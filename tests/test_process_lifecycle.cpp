#include "ParentDeathWatch.h"
#include "ProcessSingletonLock.h"

#include <catch2/catch_test_macros.hpp>

#include <sys/wait.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <string>
#include <thread>

namespace {

std::atomic<bool> gParentDeathCallbackFired{false};

void RecordParentDeath() {
  gParentDeathCallbackFired.store(true, std::memory_order_release);
}

}  // namespace

TEST_CASE("parent death channel observes writer closure", "[process][orphan][F-07]") {
  int channel[2] = {-1, -1};
  REQUIRE(::pipe(channel) == 0);
  REQUIRE(::close(channel[1]) == 0);
  REQUIRE(apm44::WaitForParentChannelClose(channel[0]));
  REQUIRE(::close(channel[0]) == 0);
}

TEST_CASE("parent death watcher invokes helper stop callback", "[process][orphan][F-07]") {
  int channel[2] = {-1, -1};
  REQUIRE(::pipe(channel) == 0);
  gParentDeathCallbackFired.store(false, std::memory_order_relaxed);
  apm44::StartParentDeathWatch(channel[0], RecordParentDeath);
  REQUIRE(::close(channel[1]) == 0);

  for (int attempt = 0; attempt < 100 &&
                        !gParentDeathCallbackFired.load(std::memory_order_acquire);
       ++attempt) {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  REQUIRE(gParentDeathCallbackFired.load(std::memory_order_acquire));
  REQUIRE(::close(channel[0]) == 0);
}

TEST_CASE("testSecondLaunchRejectedOrAdopted", "[process][singleton][F-07]") {
  const std::string path = "/tmp/apm44-singleton-test." +
                           std::to_string(static_cast<long long>(::getpid())) + ".lock";
  ::unlink(path.c_str());

  apm44::ProcessSingletonLock first;
  REQUIRE(first.acquire(path));

  const pid_t child = ::fork();
  REQUIRE(child >= 0);
  if (child == 0) {
    apm44::ProcessSingletonLock second;
    _exit(second.acquire(path) ? 1 : 0);
  }

  int status = 0;
  REQUIRE(::waitpid(child, &status, 0) == child);
  REQUIRE(WIFEXITED(status));
  REQUIRE(WEXITSTATUS(status) == 0);

  first.release();
  apm44::ProcessSingletonLock replacement;
  REQUIRE(replacement.acquire(path));
  replacement.release();
  ::unlink(path.c_str());
}
