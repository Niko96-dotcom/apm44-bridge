#pragma once

#include "hal/HalTypes.h"

#include <optional>
#include <string>

namespace apm44 {

struct FormatNegotiationError {
  std::string message;
};

class FormatNegotiator {
 public:
  std::optional<FormatNegotiationError> negotiate(BridgeDevicePair& pair);
};

}  // namespace apm44
