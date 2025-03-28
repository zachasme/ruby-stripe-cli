module StripeCLI
  # constants describing the upstream tailwindcss project
  module Upstream
    VERSION = "1.25.1"

    # rubygems platform name => upstream release filename
    NATIVE_PLATFORMS = {
      "arm64-darwin" => "stripe_#{VERSION}_mac-os_arm64.tar.gz",
      "arm64-linux" => "stripe_#{VERSION}_linux_arm64.tar.gz",
      "x86_64-darwin" => "stripe_#{VERSION}_mac-os_x86_64.tar.gz",
      "x86_64-linux" => "stripe_#{VERSION}_linux_x86_64.tar.gz"
    }
  end
end
