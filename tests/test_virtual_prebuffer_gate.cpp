#include "engine/VirtualPrebufferGate.h"

#include <catch2/catch_test_macros.hpp>

TEST_CASE("VirtualPrebufferGate waits for target fill before output",
          "[virtual_prebuffer_gate]") {
  apm44::VirtualPrebufferGate gate;
  gate.reset(882);

  REQUIRE_FALSE(gate.primed());
  REQUIRE_FALSE(gate.shouldOutput(0));
  REQUIRE_FALSE(gate.shouldOutput(881));

  REQUIRE(gate.shouldOutput(882));
  REQUIRE(gate.primed());
  REQUIRE(gate.shouldOutput(100));
}

TEST_CASE("VirtualPrebufferGate can rebuffer after an underrun",
          "[virtual_prebuffer_gate]") {
  apm44::VirtualPrebufferGate gate;
  gate.reset(441);
  REQUIRE(gate.shouldOutput(441));

  gate.forceRebuffer();
  REQUIRE_FALSE(gate.primed());
  REQUIRE_FALSE(gate.shouldOutput(440));
  REQUIRE(gate.shouldOutput(500));
}
