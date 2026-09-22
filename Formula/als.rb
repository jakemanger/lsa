# Homebrew formula. Copy this file into a tap repo named `homebrew-tap`
# (github.com/jakemanger/homebrew-tap/Formula/als.rb); then
# `brew install jakemanger/tap/als`. `make formula` fills url and sha256
# after a tag is pushed.
class Als < Formula
  desc "ls for agent sessions: list, print and resume Claude Code, Codex and pi transcripts"
  homepage "https://github.com/jakemanger/als"
  url "https://github.com/jakemanger/als/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on "jq" => :recommended

  def install
    bin.install "als"
  end

  test do
    assert_match "als 0.", shell_output("#{bin}/als --version")
  end
end
