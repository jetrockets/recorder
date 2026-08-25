# Recorder

Recorder tracks changes of your Rails models

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

The generator accepts these options:

- `--with_number_column` — adds a `number` column holding a per-item revision
  counter, maintained by a database trigger;
- `--with_index_by_user_id` — adds an index on `user_id`;
- `--with_partitions` — partitions the `recorder_revisions` table.

## Usage

To enable logging on a model you just need to include `Recorder::Observer` into the model and configure logging options for it:

``` ruby
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

There are two strategies for logging: synchronous and asynchronous. When the synchronous strategy is used, a revision record is saved immediately after a model is saved, and the async strategy moves creating of revision records to [Sidekiq](https://github.com/mperham/sidekiq).

To enable storing of such data as user_id and ip, you need to include `Recorder::Rails::ControllerConcern` to `ApplicationController`. Recorder uses [request_store](https://github.com/steveklabnik/request_store) to safely store these data on a thread level.

``` ruby
  class ApplicationController < ActionController::Base
    include Recorder::Rails::ControllerConcern
    ...
  end
```

## Known issues

The gem is under active maintenance and these defects are known as of 1.2.3:

- The per-model options above (`ignore:`, `only:`, `associations:`, `async:`)
  are not applied — every model records a full attribute snapshot regardless of
  what is passed to `recorder`.
- The migrations written by `rails generate recorder:install` do not run as
  generated, and `--with_partitions` fails during generation.
- `Recorder.enabled=` does not switch recording off.

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

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jetrockets/recorder.

## Credits

![JetRockets](https://media.jetrockets.com/jetrockets-white.png)

Recorder is maintained by [JetRockets](https://www.jetrockets.com).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

