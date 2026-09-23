source "https://rubygems.org"

gem "fastlane"

# multi_json is a transitive dependency that fastlane uses internally but that
# recent fastlane releases stopped pulling in directly. Without an explicit
# declaration CI fails with:
#   "multi_json is not part of the bundle. Add it to your Gemfile."
# ../baby-monitor hit this on its v0.14.2 release build (2026-06-05).
gem "multi_json"

# Gemfile.lock is intentionally not committed (matching ../baby-monitor and
# ../look-up): ruby/setup-ruby's `bundler-cache: true` resolves and caches it
# in CI. The tradeoff is that fastlane's version floats between releases —
# commit the lock if you ever need a byte-reproducible release toolchain.
#
# Local runs need a modern ruby: this repo's macOS system ruby is 2.6.10 with
# bundler 1.17.2, which recent fastlane refuses. CI uses ruby 3.2.
