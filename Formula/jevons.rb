class Jevons < Formula
  desc "Local AI usage monitor and dashboard"
  homepage "https://github.com/giannimassi/jevons"
  version "0.1.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/giannimassi/jevons/releases/download/v#{version}/jevons_#{version}_darwin_arm64.tar.gz"
      sha256 "PLACEHOLDER"
    end
    on_intel do
      url "https://github.com/giannimassi/jevons/releases/download/v#{version}/jevons_#{version}_darwin_amd64.tar.gz"
      sha256 "PLACEHOLDER"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/giannimassi/jevons/releases/download/v#{version}/jevons_#{version}_linux_arm64.tar.gz"
      sha256 "PLACEHOLDER"
    end
    on_intel do
      url "https://github.com/giannimassi/jevons/releases/download/v#{version}/jevons_#{version}_linux_amd64.tar.gz"
      sha256 "PLACEHOLDER"
    end
  end

  def install
    bin.install "jevons"
  end

  test do
    assert_match "jevons", shell_output("#{bin}/jevons --version")
  end
end
