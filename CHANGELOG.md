# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Per-model `recorder` options (`ignore:`, `only:`, `associations:`, `async:`)
  are applied again. Since v1.2.2 they were stored on the singleton class while
  every consumer read them off the instance, so every model silently fell back
  to the global configuration (#16).
- `recorder` options are inherited by STI subclasses. They were held in a class
  instance variable, which is not inherited, so a subclass got `{}` (#16).
- Revisions written by an STI subclass are reachable through `item.revisions`.
  `item_type` was written as the subclass name while the polymorphic
  association looks rows up by the base class name (#16).

### Changed

- **Breaking.** Per-model `ignore:` now composes with `Recorder.config.ignore`
  instead of replacing it, so a per-model list can only narrow what is recorded.
- **Breaking.** Asking for `async: true` without Sidekiq loaded now raises
  `Recorder::SidekiqNotAvailable` at declaration time. It previously raised
  `NameError: uninitialized constant Recorder::Sidekiq` on the first save when
  set through `Recorder.config.async`, and was unreachable per-model.

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
