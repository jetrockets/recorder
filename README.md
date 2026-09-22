# Recorder

[![CI](https://github.com/jetrockets/recorder/actions/workflows/ci.yml/badge.svg)](https://github.com/jetrockets/recorder/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/recorder)](https://rubygems.org/gems/recorder)

Recorder tracks changes of your Rails models. Each create, update, and destroy on
an observed model writes a `recorder_revisions` row holding an attribute snapshot,
the changes, and — when the controller concern is included — the user and IP
behind the request.

## Requirements

- PostgreSQL — revisions are stored in `jsonb` and `inet` columns
- Ruby and Rails per the table below

| Rails | Supported Ruby |
|-------|----------------|
| 6.1   | 3.0 – 3.3      |
| 7.0   | 3.0 – 3.3      |
| 7.1   | 3.0 – 3.4      |
| 7.2   | 3.1 – 3.4      |
| 8.0   | 3.2 – 3.4      |
| 8.1   | 3.2 – 3.4      |

Rails 6.1 and 7.0 cannot run on Ruby 3.4 — they require `mutex_m`, which left the
default gems in that release. Every combination in the table is exercised in CI.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'recorder'
```

And then execute:

    $ bundle

Generate the migration for the `recorder_revisions` table:

    $ rails generate recorder:install

The generator writes the migration but does not run it. Run it yourself:

    $ rails db:migrate

The generator accepts one option:

- `--with_index_by_user_id` — adds an index on `user_id`.

## Usage

### Observing a model

Include `Recorder::Observer` into the model and configure logging options for it:

```ruby
class Post < ActiveRecord::Base
  include ::Recorder::Observer

  recorder only: %i[title tags],
    associations: {
      author: { only: %i[full_name] },
      category: { only: %i[name slug] }
    }
end
```

Recorder supports the following options:

 * `ignore: [array]` - attributes that are ignored on logging;
 * `only: [array]` - only these attributes are logged, other attributes are ingored;
 * `associations: {hash} (hash)` - allows to set what associations will be logged alongside with the model. For each association you can also set ignore and only options;
 * `async: bool` - a logging strategy (true - asynchronous, false - synchronous).
 * `changes: Proc | Symbol` - extra entries to merge into a revision's `changes`. A Proc
   is evaluated on the record, a Symbol names a method on it; both receive the event
   (`:create`, `:update` or `:destroy`) and return a hash of `name => [old, new]`, or
   `nil` for nothing. Anything else raises `ArgumentError` where `recorder` is called.

The entries are merged after `only:` and `ignore:` have been applied, so those
filters never drop them, and a key that matches an attribute replaces that
attribute's entry. An update that reports only custom entries still records a
revision.

Inside the callback, read `saved_changes` and `saved_change_to_<attribute>?`, not
`<attribute>_changed?`: the callback runs from `after_create`/`after_update`, where
the dirty state has already been reset.

`Recorder::Changeset` rebuilds the previous and next versions by assigning each
change onto a copy of the record, and skips what it cannot assign: a key that is
not an attribute, and any value that is not a two-element `[old, new]` pair. To display such
a key, define `previous_<key>`/`next_<key>` on the model's changeset class, and
pick a name that `Recorder::Changeset` does not already answer to.

These per-model options, `changes:` included, do not reach the recorder yet — see [Known issues](#known-issues).
Until they do, every observed model records a full attribute snapshot, filtered
only by the global `Recorder.config.ignore`. Options declared as an instance
method are read, so that is the way to opt into any of them today:

```ruby
def recorder_options
  {ignore: %i[identifier], changes: :extra_changes}
end
```

### Global configuration

```ruby
Recorder.config do |config|
  config.ignore = %i[created_at updated_at]
  config.async = false
  config.sidekiq_options = {queue: 'recorder', retry: 10, backtrace: true}
end
```

`ignore` defaults to `[]`, `async` to `false`, and `sidekiq_options` to the hash
shown above.

There are two strategies for logging: synchronous and asynchronous. When the synchronous strategy is used, a revision record is saved immediately after a model is saved, and the async strategy moves creating of revision records to [Sidekiq](https://github.com/sidekiq/sidekiq). Under the async
strategy the revision is enqueued to `Recorder::Sidekiq::RevisionsWorker` two
seconds out; the worker is loaded by the railtie when `Sidekiq` is defined.

### Recording the current user

To enable storing of such data as user_id and ip, you need to include `Recorder::Rails::ControllerConcern` to `ApplicationController`. Recorder uses [request_store](https://github.com/steveklabnik/request_store) to safely store these data on a thread level.

``` ruby
  class ApplicationController < ActionController::Base
    include Recorder::Rails::ControllerConcern
    ...
  end
```

The concern reads `current_user`; override `recorder_user_id` to name a different
method. Override `recorder_meta` to store a hash alongside every revision. A
revision without a user is valid — `user_id` stays `nil`.

### Turning recording off

`Recorder::Manager` suspends recording for the current request or thread:

```ruby
class Importer
  include Recorder::Manager

  def call
    recorder_disabled! do
      # nothing recorded in here
    end
  end
end
```

The block form re-enables recording on the way out, including when the block
raises. Called without a block, `recorder_disabled!` stays in effect until
`recorder_enabled!`.

### Reading revisions

Observed models get a `revisions` association:

```ruby
revision = post.revisions.ordered_by_created_at.first

revision.event        # "update"
revision.data         # {"attributes" => {...}, "changes" => {...}, "associations" => {...}}
revision.user_id
revision.action_date
```

`data` carries a complete attribute snapshot on every event, not only what
changed:

- `attributes` — every attribute of the record as it stood when the callback
  ran, filtered by the model's `only:` or `ignore:` and, failing those, by
  `Recorder.config.ignore`. Always present.
- `changes` — the same filter applied to `saved_changes`, as
  `name => [old, new]`, plus any entries from `changes:`. Omitted when that
  leaves nothing.
- `associations` — those two keys again, one entry per association named in
  `associations:`. Omitted when no association reports anything.

The snapshot is the contract, not an accident of the implementation: a revision
is self-contained, so reconstructing a record at a point in time does not mean
replaying every prior diff. It is also what keeps a `destroy` revision useful,
since the row it describes is gone.

An `update` records a revision only when the record or one of its recorded
associations reports a change; `create` and `destroy` always record one.

`#item_changeset` wraps `data['changes']` in a `Recorder::Changeset`, which reads
the values back as the model's own types:

```ruby
changeset = revision.item_changeset

changeset.keys                        # attributes that changed
changeset.previous(:title)            # value before the change
changeset.next(:title)                # value after it
changeset.human_attribute_name(:title)
changeset.previous_version            # a copy of the record with the old values
```

Changed associations are reachable the same way:

```ruby
revision.changed_associations         # ["author"]
revision.association_changeset('author')
```

To render a changeset yourself, define `PostChangeset` — the class is looked up
as `"#{model}Changeset"` — or point at another one with a
`recorder_changeset_class` class method on the model. Otherwise
`Recorder::Changeset` is used.

## Known issues

The gem is under active maintenance and these defects are known as of 1.3.0:

- The per-model options above (`ignore:`, `only:`, `associations:`, `async:`)
  are not applied. `Recorder::Tape` asks the record instance for
  `recorder_options`, but `Recorder::Observer` defines that method on the class,
  so the lookup always falls back to `{}` — every observed model records a full
  attribute snapshot, synchronously. Global configuration is unaffected.
- `Recorder.enabled=` does not switch recording off. It writes to
  `Recorder.config`, which nothing on the recording path reads — the gates are in
  `Recorder.store`, which `Recorder::Manager` drives.
- Collection associations are never recorded. `associations:` handles only
  singular associations; a `has_many` reflection is skipped without a warning.
- A `destroy` revision carries a `changes` key describing the record's last
  *update*. `destroy` does not clear `saved_changes`, and `data` is built the
  same way for every event. The `attributes` snapshot is the accurate record of
  what was deleted.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

The specs need a PostgreSQL server. Connection settings are read from the
environment — `RECORDER_DB_HOST`, `RECORDER_DB_PORT`, `RECORDER_DB_USERNAME`,
`RECORDER_DB_PASSWORD`, `RECORDER_DB_NAME` — and default to `postgres:postgres`
on `localhost:5432` against a `recorder_test` database, which must already exist.

`rake spec` runs against whichever Rails version the root `Gemfile` resolves to.
To run against a specific one, use the appraisal gemfiles:

```bash
bundle exec appraisal install            # once, to generate gemfiles/
bundle exec appraisal rails-7.2 rake spec
```

CI runs the suite across the whole Ruby × Rails matrix above, plus `bundle exec
rubocop`. Both must pass before a pull request merges.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, bump `Recorder::VERSION` and move the `[Unreleased]`
changelog entries under it in a pull request. Once that merges, tag the merge
commit and push the tag:

```bash
git fetch origin
git tag vX.Y.Z origin/master
git push origin vX.Y.Z
```

The Release workflow then runs CI against the tagged commit, checks the tag
matches `Recorder::VERSION`, publishes the gem to [rubygems.org](https://rubygems.org)
through trusted publishing, and creates the GitHub release from the changelog.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jetrockets/recorder.

## Credits

![JetRockets](https://media.jetrockets.com/jetrockets-white.png)

Recorder is maintained by [JetRockets](https://www.jetrockets.com).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
