# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Support for Rails 7.0, 7.1, 7.2, 8.0, and 8.1. Rails 6.1 remains supported.
- Support for Ruby 3.3 and 3.4. Ruby 3.0 remains the minimum.
- Declared and tested the supported Ruby versions (#10).
- The specs and RuboCop now run in GitHub Actions (#9).
- Gem metadata: `source_code_uri`, `changelog_uri`, `bug_tracker_uri`, and
  `rubygems_mfa_required`.

### Changed

- `activerecord` and `activesupport` requirements widen from `~> 6.1` to
  `>= 6.1, < 9`, and the `< 3.4` Ruby ceiling is removed. Rails 6.1 and 7.0
  cannot run on Ruby 3.4; every other combination is exercised in CI.
- The released gem now ships only `lib/`, the README, the LICENSE, and this
  changelog. Previous releases also carried repository scaffolding — CI
  configuration, `Rakefile`, `bin/`, and dotfiles — that a host app never loads.
- `recorder_revisions.item_id` and `recorder_revisions.user_id` are now
  `bigint`. Rails has defaulted primary keys to `bigint` since 5.1, so the
  `integer` columns could not hold a key from any table this gem audits once it
  passed 2,147,483,647. No release since Rails 5.0 shipped a migration that could
  run; installs from the 0.1.x line on Rails 4 have the narrow columns and are
  unaffected, because the gem ships no migration that alters an existing table
  (#18).

### Removed

- `pg` is no longer a runtime dependency. Revisions still require PostgreSQL
  column types, but the adapter is the host application's to declare, so the
  gem no longer forces `pg` into its bundle.
- The `--with_partitions` generator option. It dispatched to a template that was
  never added to the gem, so the run wrote the first migration and then aborted,
  leaving a partial install. It never completed once (#18).
- The `--with_number_column` generator option. The `number` column it added was
  never read by the gem, and the migration it generated could not run on any
  Rails this gem supports, so there is no working installed base. Anyone who has
  the column keeps it — the counter lives in a trigger in their own schema,
  which this does not touch, and the gem never writes the column. Optional
  cleanup, including a working `DROP TRIGGER`, is in #14 — the `down` the gem
  originally shipped is a syntax error and cannot roll it back (#14).

### Fixed

- `rails generate recorder:install` now produces migrations that run. The
  templates subclassed a bare `ActiveRecord::Migration`, which Rails has
  rejected since 5.0, so `rails db:migrate` raised on the only documented way to
  install the gem. The version is templated from the host app's Rails (#18).
- `Recorder.version` returns the version instead of raising `TypeError`. It
  scoped into `VERSION::STRING`, but `VERSION` is a `String` (#17).
- `recorder_disabled!` re-enables recording when the block raises. The re-enable
  was skipped on the exception path, so recording stayed off for the rest of the
  request or job and every later save went silently unaudited (#17).
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
