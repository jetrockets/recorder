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

These per-model options do not reach the recorder yet — see [Known issues](#known-issues).
Until they do, every observed model records a full attribute snapshot, filtered
only by the global `Recorder.config.ignore`.

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

The gem is under active maintenance and these defects are known as of 1.2.3:

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

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jetrockets/recorder.

## Credits

![JetRockets](https://media.jetrockets.com/jetrockets-white.png)

Recorder is maintained by [JetRockets](https://www.jetrockets.com).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
