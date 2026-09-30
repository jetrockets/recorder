# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## What this is

`recorder` is a Ruby gem, not an application. It hooks into a host Rails app and writes a `recorder_revisions` row each time an observed ActiveRecord model is created, updated or destroyed. The only Rails app in the repo is `spec/dummy`, which exists for the specs.

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

The specs need a running PostgreSQL (revisions use `jsonb` and `inet`). Connection settings come from `RECORDER_DB_HOST`, `RECORDER_DB_PORT`, `RECORDER_DB_USERNAME`, `RECORDER_DB_PASSWORD` and `RECORDER_DB_NAME`; the defaults are in `spec/dummy/config/database.yml`. The database must exist; `spec/rails_helper.rb` runs the dummy app's migrations itself on every run.

CI runs the suite across a Ruby × Rails matrix (`.github/workflows/ci.yml`) plus rubocop. Code has to work on every combination in it, so check version-specific APIs against the oldest supported Ruby and Rails in `recorder.gemspec` before using them.

## Structure

- `lib/recorder.rb` — entry point; requires everything else and defines the top-level `Recorder` API.
- `lib/recorder/` — the library: `Observer`, `Tape` (with `Tape::Data` and `Tape::Record`), `Revision`, `Changeset`, `Config`, `Store`, `Manager`.
- `lib/recorder/rails/` — the controller concern and the railtie.
- `lib/recorder/sidekiq/` — the worker behind async recording.
- `lib/generators/recorder/` — the `recorder:install` generator and its migration templates.
- `spec/dummy/` — a minimal Rails app the specs boot; its models and migrations are spec fixtures.
- `Appraisals` and `gemfiles/` — one gemfile per supported Rails version.

## Architecture

The flow of one recorded change, in the order the code runs:

1. **Request context** — `Recorder::Rails::ControllerConcern` adds `before_action`s that put `user_id`, `ip`, `action_date` and `meta` into `Recorder.store.params`.
2. **Opt-in** — a model includes `Recorder::Observer` and calls `recorder(...)`, which registers `after_create`, `after_update` and `after_destroy` callbacks. Each one builds a `Recorder::Tape` for the record.
3. **Payload** — `Recorder::Tape::Data#data_for` builds `{attributes:, changes:, associations:}`: an attribute snapshot, the record's `saved_changes`, and the same two keys per recorded association.
4. **Persist** — `Recorder::Tape::Record#record` merges the request context with the payload and either creates a `Recorder::Revision` or schedules `Recorder::Sidekiq::RevisionsWorker`, which creates it later.
5. **Read back** — `Recorder::Revision#item_changeset` wraps `data['changes']` in a changeset class, resolved as the model's `recorder_changeset_class`, then `"#{Model}Changeset"`, then `Recorder::Changeset`.

There are two separate kinds of state:

- `Recorder.config` is a process-wide singleton holding global settings.
- `Recorder.store` wraps `RequestStore`, so it is per-request: the request params from step 1 and the flag `Recorder::Manager` toggles.

Sidekiq is not a dependency of the gem. The railtie requires the worker only when `Sidekiq` is defined.

## Specs

- `spec/rails_helper.rb` resets the three places Recorder keeps state between examples: database rows (transactions), the `Config` singleton, and `RequestStore` plus the memoised `Recorder.store`. New state that outlives an example needs resetting there too.
- `spec/support/sidekiq_stand_in.rb` defines a minimal `Sidekiq::Worker` so the worker class loads, then removes the `Sidekiq` constant so `defined?(Sidekiq)` stays false for the rest of the suite.
- Examples run in random order.

## Conventions

- Add user-visible changes to `CHANGELOG.md` under `[Unreleased]` (Keep a Changelog format), and update the README when public behaviour changes.
- Leave `Recorder::VERSION` alone in feature PRs. A release is its own PR that bumps the version and moves the changelog entries; pushing a `vX.Y.Z` tag on master then triggers the Release workflow, which publishes to RubyGems.
- `gemfiles/*.gemfile` are generated from `Appraisals`; edit `Appraisals` and re-run `bundle exec appraisal install`. The lockfiles are gitignored.
- The gemspec lists the files that ship in the gem explicitly; a new top-level file is not packaged unless it is added there.
