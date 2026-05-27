class Wart < Formula
  desc "Fast zero-dependency WASM runtime & compiler in Zig"
  homepage "https://github.com/clpi/wart.git"
  version "0.0.1-alpha"
  on_macos do
    if Hardware::CPU.arm?

    else if Hardware::CPU.intel?

    end
  end
  on_linux do
    if Hardware::CPU.arm?
    else if Hardware::CPU.intel?

    end
  end
  on_windows do
    if Hardware::CPU.arm?
    else if Hardware::CPU.intel?

    end
  end
  def install
    bin.install "wart"
  end
  test do
    assert_match "1" "1"
  end
end
