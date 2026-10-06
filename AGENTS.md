# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## What this is

`recorder` is a Ruby gem, not an application. It hooks into a host Rails app and writes a `recorder_revisions` row each time an observed ActiveRecord model is created, updated or destroyed. The only Rails app in the repo is `spec/dummy`, which exists for the specs.

## Invariants

Recorder is an audit trail. Host apps build compliance, support and debugging features on top of it and assume the history is complete and correct. Every change to the gem has to keep these guarantees:

1. **No lost actions.** Every create, update and destroy of an observed record produces a revision. The only ways to skip one are the explicit opt-outs: the `only:` and `ignore:` options, `Recorder.config.ignore`, `recorder_disabled!` and `Recorder.enabled = false`. An update that touches nothing but ignored attributes is the one case that writes no revision.
2. **History rebuilds the record.** Replaying a record's revisions yields its final state, ignored attributes aside. Each revision carries enough to stand on its own: a snapshot of the recorded attributes plus the changes that led to it.
3. **No phantom actions.** A revision describes a change that was really persisted. A change that was rolled back leaves no revision behind.
4. **Revisions are append-only.** The gem creates revisions and never updates or deletes them. Cleaning up history is the host app's decision.
5. **Attribution belongs to the moment of the action.** `user_id`, `ip`, `action_date` and `meta` come from the request that made the change, no matter when the row is written.
6. **The revision is written in the save transaction.** The record and its revision commit or roll back together, which is what keeps 1, 3, 7 and 9. Deferring the write past commit, to a background job or an `after_commit` hook, gives up at least one of them.
7. **History stays in order.** The revisions of one record can be sorted into the order the changes happened.
8. **Old revisions stay readable.** Rows written by earlier versions of the gem live in host databases forever. The shape of `data` (`attributes`, `changes`, `associations`) and the meaning of each column are a public contract: extend them, do not rename, repurpose or drop them.
9. **Recording does not alter the host app.** Observing a model never changes the record, its attributes or the outcome of the save. When a revision cannot be written, that surfaces as an error; it is never swallowed.

A change that touches how revisions are built or written needs a spec proving the affected guarantees still hold. If a change cannot keep one of them, stop and raise it with the maintainers instead of trading it away.

## Commands

```bash
bin/setup                                  # bundle install + create the test database
bundle exec rspec                          # whole suite, against the root Gemfile's Rails
bundle exec rspec spec/recorder/tape/data_spec.rb       # one file
bundle exec rspec spec/recorder/tape/data_spec.rb:42    # one example
bundle exec rubocop                        # lint (jetrockets-standard)
bundle exec rubocop -a                     # lint with safe autocorrect

bundle exec appraisal install              # once, generates gemfiles/*.gemfile.lock
bundle exec appraisal <name> rspec         # suite against one Rails version; names are in Appraisals
```

The specs need a running PostgreSQL (revisions use `jsonb` and `inet`). Connection settings come from `RECORDER_DB_HOST`, `RECORDER_DB_PORT`, `RECORDER_DB_USERNAME`, `RECORDER_DB_PASSWORD` and `RECORDER_DB_NAME`; the defaults are in `spec/dummy/config/database.yml`. The database must exist; `spec/rails_helper.rb` runs the dummy app's migrations itself on every run. Every run also writes a SimpleCov line and branch coverage report to `coverage/index.html`.

CI runs the suite across a Ruby × Rails matrix (`.github/workflows/ci.yml`) plus rubocop. Code has to work on every combination in it, so check version-specific APIs against the oldest supported Ruby and Rails in `recorder.gemspec` before using them.

## Structure

- `lib/recorder.rb` — entry point; requires everything else and defines the top-level `Recorder` API.
- `lib/recorder/` — the library: `Observer`, `Tape` (with `Tape::Data` and `Tape::Record`), `Revision`, `Changeset`, `Config`, `Store`, `Manager`.
- `lib/recorder/rails/` — the controller concern.
- `lib/generators/recorder/` — the `recorder:install` generator and its migration templates.
- `spec/dummy/` — a minimal Rails app the specs boot; its models and migrations are spec fixtures.
- `Appraisals` and `gemfiles/` — one gemfile per supported Rails version.

## Architecture

The flow of one recorded change, in the order the code runs:

1. **Request context** — `Recorder::Rails::ControllerConcern` adds `before_action`s that put `user_id`, `ip`, `action_date` and `meta` into `Recorder.store.params`.
2. **Opt-in** — a model includes `Recorder::Observer` and calls `recorder(...)` once per class hierarchy, which stores the options and registers `after_create`, `after_update` and `after_destroy` callbacks. Subclasses inherit both. Each callback builds a `Recorder::Tape` for the record.
3. **Payload** — `Recorder::Tape::Data#data_for` builds `{attributes:, changes:, associations:}`: an attribute snapshot, the record's `saved_changes`, and, on create and destroy, an attribute snapshot per recorded association.
4. **Persist** — `Recorder::Tape::Record#record` merges the request context with the payload and creates a `Recorder::Revision`, still inside the save transaction.
5. **Read back** — `Recorder::Revision#item_changeset` wraps `data['changes']` in a changeset class, resolved as the model's `recorder_changeset_class`, then `"#{Model}Changeset"`, then `Recorder::Changeset`.

There are two separate kinds of state:

- `Recorder.config` is a process-wide singleton holding global settings.
- `Recorder.store` wraps `RequestStore`, so it is per-request: the request params from step 1 and the flag `Recorder::Manager` toggles. `RequestStore`'s Rack middleware clears it after each request; outside a request, in a background job for instance, nothing reliably does, so it lasts as long as the thread.

A change is recorded only while both the process-wide `Recorder.enabled?` and the per-request flag are on. Code that decides whether to record calls `Recorder.recording?`, never one of the flags alone.

## Specs

- `spec/rails_helper.rb` resets the three places Recorder keeps state between examples: database rows (transactions), the `Config` singleton, and `RequestStore` plus the memoised `Recorder.store`. New state that outlives an example needs resetting there too.
- To roll a save back inside an example, open `transaction(requires_new: true)` and raise `ActiveRecord::Rollback`; `spec/recorder/tape/record_spec.rb` does this.
- Examples run in random order.

## Conventions

- Add user-visible changes to `CHANGELOG.md` under `[Unreleased]` (Keep a Changelog format), and update the README when public behaviour changes.
- Leave `Recorder::VERSION` alone in feature PRs. A release is its own PR that bumps the version and moves the changelog entries; pushing a `vX.Y.Z` tag on master then triggers the Release workflow, which publishes to RubyGems.
- `gemfiles/*.gemfile` are generated from `Appraisals`; edit `Appraisals` and re-run `bundle exec appraisal install`. The lockfiles are gitignored.
- The gemspec lists the files that ship in the gem explicitly; a new top-level file is not packaged unless it is added there.
