# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Declared and tested the supported Ruby versions (#10).
- The specs and RuboCop now run in GitHub Actions (#9).
- Gem metadata: `source_code_uri`, `changelog_uri`, `bug_tracker_uri`, and
  `rubygems_mfa_required`.

### Changed

- The released gem now ships only `lib/`, the README, the LICENSE, and this
  changelog. Previous releases also carried repository scaffolding — CI
  configuration, `Rakefile`, `bin/`, and dotfiles — that a host app never loads.

### Fixed

- Made the spec suite runnable and trustworthy again (#8).

## [1.2.3] - 2023-04-25

### Fixed

- A revision is created when an item's associations change.
- No revision is created for an `:update` event when nothing changed.

## [1.2.2] - 2022-11-17

### Fixed

- Refactoring for full Rails 6 compatibility.

## [1.2.1] - 2022-11-16

### Fixed

- Fixed parsing of empty associations.

## [1.2.0] - 2022-11-15

### Added

- Rails 6 support.

## [1.1.1] - 2021-09-13

Releases at and before 1.1.1 predate this changelog. See the
[commit history](https://github.com/jetrockets/recorder/commits/master) for
details.

[Unreleased]: https://github.com/jetrockets/recorder/compare/v1.2.3...HEAD
[1.2.3]: https://github.com/jetrockets/recorder/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/jetrockets/recorder/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/jetrockets/recorder/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/jetrockets/recorder/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/jetrockets/recorder/releases/tag/v1.1.1
