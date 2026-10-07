# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking.** `recorder` can be called once per class hierarchy, and calling
  it again, in the same class, a subclass or a parent, raises `ArgumentError`.
  Every call used to register the create, update and destroy callbacks anew, so
  a model that declared it twice wrote two identical revisions per event. A
  subclass that needs different options defines a `recorder_options` instance
  method instead. A declaration that runs twice on one class, such as one in a
  `to_prepare` block on a class that is not reloaded, raises too; it used to
  add another revision per event on every run.
- **Breaking.** `Recorder.info` raises `ArgumentError` for the columns Recorder
  writes itself: `created_at`, `id`, `item_type`, `item_id`, `event` and
  `data`. A `created_at` set through it used to overwrite every following
  revision's, so `created_at` was not reliably when the revision was written;
  to date revisions otherwise, set `action_date`. The other keys were silently
  overwritten by the revision's own values.

### Removed

- **Breaking.** Asynchronous recording: the `async:` and `delay:` options,
  `Recorder.config.async`, `Recorder.config.sidekiq_options` and
  `Recorder::Sidekiq::RevisionsWorker`, with the railtie that loaded it. Every
  revision is written in the save transaction, so the record and its revision
  commit or roll back together. The job was pushed from inside that transaction,
  so a save that rolled back still wrote a revision once the job ran, and the
  revision's `created_at` and `id` followed the job rather than the change.
  `async:` and `delay:` passed to `recorder` have no effect, as they had none
  from 1.2.2 on; remove them. Setting `Recorder.config.async` or
  `Recorder.config.sidekiq_options` raises `NoMethodError`. An app that set
  `Recorder.config.async = true` should set it to `false` on 1.x first and let
  the jobs already pushed finish, the scheduled and retrying ones included,
  before upgrading: a job left behind fails once the worker class is gone, and
  its revision is never written.

### Fixed

- **Breaking.** `Recorder.enabled = false` switches recording off, for the
  whole process. It used to report recording as off while every change was
  still recorded, so a script that set it, such as a backfill or a data
  migration, starts leaving no revisions behind.
- `recorder_disabled!` with a block restores the state it found, so one nested
  in another, or called while recording is already off, leaves it off. It used
  to turn recording back on when its block ended, and what followed was recorded.
- **Breaking.** The options passed to `recorder` — `ignore:`, `only:`,
  `associations:` and `changes:` — are applied again. Since 1.2.2 they were
  stored on the class while the recorder read them off the record, so every
  model fell back to the global configuration. Models that
  declare options now record what they asked for, which changes existing audit
  trails going forward:
  - `only:` and `ignore:` shrink the snapshot, and an update touching only
    excluded attributes no longer writes a revision.
  - A per-model `ignore:` replaces `Recorder.config.ignore` for that model, so
    globally ignored attributes it does not repeat start being recorded. The
    same holds for `only:`: an attribute it lists is recorded even if the
    global list ignores it. To keep the global list, repeat it, as in
    `ignore: [*Recorder.config.ignore, :token]`.
  - `associations:` adds an `associations` key to create and destroy revisions.

  A `recorder_options` instance method on the model still takes precedence, and
  replaces the declared options rather than merging with them.
- **Breaking.** A subclass, STI included, records under the options its parent
  passed to `recorder`. It used to record as if no options were given, so a
  subclass's revisions change shape the way a declaring model's do above.
- A `recorder_options` instance method defined as private is used. It used to
  be ignored, and the model recorded as if no options were given.
- **Breaking.** Revisions of an STI subclass store the base class name in
  `item_type`, the model's `polymorphic_name`, so `revisions` finds them. They
  stored the subclass name, which no Active Record lookup through `item` or
  `revisions` matches, so `revisions` on a subclass instance returned nothing.
  Queries that filter `item_type` by a subclass name stop matching new rows;
  filter by the base class, or by the snapshot's inheritance column. Existing
  rows are not rewritten; the README has a snippet that does it.
- An `action_date` set through `Recorder.info` is recorded, under a symbol or a
  string key. Every revision used to be dated with the server's `Date.today`
  instead, so a revision could not be backdated. A nil or blank one falls back
  to today.
- `Recorder.info` stores its keys as symbols, so a string key replaces the
  symbol one. Both used to be kept, and which reached the revision depended on
  the order they were set in.
- **Breaking.** `action_date` is today in the application's time zone,
  `Date.current`, whether the controller concern sets it or nothing does. It
  was the server's date, so an app whose `config.time_zone` differs from the
  server's records a different date for changes made near midnight. Existing
  rows keep the server's date, so a trail that spans the upgrade holds both.
- `Revision.ordered_by_created_at` orders revisions with the same `created_at`
  by `id`, newest first. They used to come back in whatever order the database
  returned them, so the latest of two revisions written in the same instant
  was not reliably `first`.
- **Breaking.** A revision records each association named in `associations:`
  as an `attributes` snapshot, on `create` and `destroy` only. It used to add
  the associated record's `saved_changes`, which describe that in-memory
  record's last save rather than the one being recorded. So a revision could
  claim an association changed when it had not, and an update touching only
  excluded attributes still wrote a revision whenever the associated record had
  been saved earlier in the process. An associated record's changes belong to
  its own revisions, so an edit saved through the item, with `autosave:` or
  nested attributes, is recorded only when the associated model records itself
  too. Replacing a `belongs_to` target shows up as the foreign key in the item's
  `changes`; replacing a `has_one` target shows up only in the associated
  records' own revisions. `update` revisions no longer carry `associations`.
- **Breaking.** `Revision#changed_associations` lists only the associations
  that hold changes, where it listed every recorded one.
  `Revision#association_changeset` returns `nil` when the revision holds no
  changes for that association, or when the item is gone or no longer has that
  association set. It used to raise `KeyError` or `NoMethodError`.
- **Breaking.** A `destroy` revision's `changes` hold only the entries from
  `changes:`, and the key is omitted when there are none. They used to carry
  the record's `saved_changes`, which `destroy` does not clear, so destroying a
  record saved earlier through the same instance repeated that save's diff, as
  if the deletion had changed those attributes. The `attributes` snapshot is
  unchanged. Existing destroy revisions keep the stale `changes`.

## [1.4.0]

### Added

- README coverage of what a revision's `data` holds: the complete attribute
  snapshot on every event, when `changes` and `associations` are present, and
  which events record a revision at all. No behaviour changes — the snapshot is
  what the gem has always written, and it is now written down.
- A known issue for the `changes` key on `destroy` revisions, which describes
  the record's last update rather than the deletion.
- A `changes:` option on `recorder` that merges extra entries into a revision's
  `changes`. It takes a Proc evaluated on the record or the name of a method on it;
  both receive the event.

### Changed

- `Recorder::Revision` declares both `belongs_to :user` and `belongs_to :item`
  with `optional: true`. The associations have always been optional in practice,
  but only because the gem is required before the Active Record railtie applies
  `belongs_to_required_by_default`, so the reflections are built while the
  default is still off. Had that ordering ever shifted, every revision without a
  user would have failed validation, and so would every `destroy` revision,
  which is written after its item's row is deleted. `Tape::Record#record` calls
  `create`, not `create!`, so those revisions would have been dropped with
  nothing raised anywhere. Recorded revisions are unchanged.

### Fixed

- `Recorder::Changeset#previous` and `#next` no longer raise `NoMethodError` when
  the changes carry a key that is not an attribute of the model, and skip values
  that are not a two-element `[old, new]` pair rather than indexing into them.

## [1.3.0] - 2026-09-16

### Added

- Support for Rails 7.0, 7.1, 7.2, 8.0, and 8.1. Rails 6.1 remains supported.
- Support for Ruby 3.3 and 3.4. Ruby 3.0 remains the minimum.
- Declared and tested the supported Ruby versions (#10).
- The specs and RuboCop now run in GitHub Actions (#9).
- Releases are published to RubyGems.org from GitHub Actions when a version tag
  is pushed (#22).
- Gem metadata: `source_code_uri`, `changelog_uri`, `bug_tracker_uri`, and
  `rubygems_mfa_required`.
- README coverage of the public API: configuration, `Recorder.meta=`,
  `recorder_disabled!`, and the association tracking options (#20).

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

- Asynchronous recording no longer enqueues job arguments Sidekiq rejects. The
  `meta` hash supplied through `Recorder.meta=` reached the worker with its
  original keys and values, and Sidekiq raises on arguments that are not JSON
  native from 7.0 onwards. Because the raise happened inside an `after_create`,
  it rolled back the host application's own write. The enqueued payload is now
  normalised to JSON natives in full (#19).
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

[Unreleased]: https://github.com/jetrockets/recorder/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/jetrockets/recorder/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/jetrockets/recorder/compare/v1.2.3...v1.3.0
[1.2.3]: https://github.com/jetrockets/recorder/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/jetrockets/recorder/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/jetrockets/recorder/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/jetrockets/recorder/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/jetrockets/recorder/releases/tag/v1.1.1
