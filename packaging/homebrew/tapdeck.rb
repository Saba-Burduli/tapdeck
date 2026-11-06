# Homebrew cask for TapDeck. Publish it in a tap repo (Saba-Burduli/homebrew-tap,
# as Casks/tapdeck.rb), then users install with:
#   brew install --cask saba-burduli/tap/tapdeck
#
# After each release, set `version` and `sha256` (printed by
# scripts/package-release.sh and shown in the release notes).
cask "tapdeck" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/Saba-Burduli/tapdeck/releases/download/v#{version}/TapDeck-#{version}.dmg"
  name "TapDeck"
  desc "Turn the trackpad into a shortcut panel with multi-finger taps"
  homepage "https://github.com/Saba-Burduli/tapdeck"

  depends_on macos: ">= :sonoma"

  app "TapDeck.app"

  uninstall quit: "com.saba-burduli.tapdeck"

  zap trash: "~/Library/Application Support/TapDeck"
end
