cask "naplocker" do
  version "1.0.0"
  sha256 "4a9b1a0d1f46cb8dc2db6beddb91a15e22b133fb807e62a898ccd0b5b08a8563"

  url "https://github.com/nileshkk9/NapLocker/releases/download/v#{version}/NapLocker.zip",
      verified: "github.com/nileshkk9/NapLocker/"
  name "NapLocker"
  desc "Menu bar app that requires Touch ID when a protected app launches"
  homepage "https://github.com/nileshkk9/NapLocker"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "NapLocker.app"

  # Ad-hoc signed (no Developer ID / notarization). Homebrew applies
  # Gatekeeper quarantine to cask downloads; strip it so the app can launch.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/NapLocker.app"]
  end

  uninstall quit: "com.naplocker.NapLocker"

  zap trash: [
    "~/Library/Application Support/NapLocker",
  ]
end
