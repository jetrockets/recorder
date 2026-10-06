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

 * `ignore: [array]` - attributes that are ignored on logging. Replaces `Recorder.config.ignore` for this model rather than adding to it;
 * `only: [array]` - only these attributes are logged, other attributes are ignored. `Recorder.config.ignore` does not apply, so a listed attribute is logged even if the global list ignores it. Takes precedence over `ignore:`;
 * `associations: {hash} (hash)` - allows to set what associations will be logged alongside with the model, as a snapshot on `create` and `destroy`. For each association you can also set ignore and only options, which follow the same rules; an association given neither falls back to `Recorder.config.ignore`;
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

A model that needs to decide its options per record can define
`recorder_options` as an instance method. It replaces what was passed to
`recorder` rather than merging with it, so it has to return every option the
model needs:

```ruby
def recorder_options
  {ignore: %i[identifier], changes: :extra_changes}
end
```

#### Subclasses

A subclass, STI or not, records under the options its parent passed to
`recorder` and needs no declaration of its own. `recorder` can be called once per
class hierarchy, in the topmost class that records: calling it again, in the same
class, a subclass or a parent, raises `ArgumentError`. So does a declaration that
runs twice on one class, such as one in a `to_prepare` block on a class that is
not reloaded. A subclass that needs different options defines
`recorder_options`, public or private, and can build on the parent's with `super`:

```ruby
class Bond < Instrument
  def recorder_options
    super.merge(ignore: [*super[:ignore], :coupon])
  end
end
```

`super` returns the parent's options, by default the hash it declared, which
every subclass shares: build a new one, such as `super.merge(...)` or
`[*super[:ignore], :coupon]`, rather than changing it in place. The result is
applied as if it had been declared. The usual rules hold: `only:` takes
precedence over `ignore:`, so adding to `ignore:` has no effect under a parent
that declares `only:`, and an `ignore:` replaces `Recorder.config.ignore`, so a
subclass adding one under a parent that declares none has to repeat the global
list.

### Global configuration

```ruby
Recorder.config do |config|
  config.ignore = %i[created_at updated_at]
end
```

`ignore` defaults to `[]`.

`ignore` applies only to models, and associations, that declare neither `only:`
nor `ignore:`. A model that declares either uses its own list alone, so to keep
the global list and add to it, repeat it:

```ruby
recorder ignore: [*Recorder.config.ignore, :internal_id]
```

This reads the global list when the model loads, so configure `Recorder` in an
initializer.

### When a revision is written

A revision is written from the model's `after_create`, `after_update` and
`after_destroy` callbacks, in the same database transaction as the save. The
record and its revision commit together, and a save that rolls back leaves no
revision behind.

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

A revision's `action_date` is today in the application's time zone,
`Date.current`. To date revisions otherwise, such as an import replaying past
changes, set it yourself; it holds for the rest of the request or thread:

```ruby
Recorder.info = {action_date: Date.new(2020, 1, 1)}
```

`created_at` is always when the revision was written. `Recorder.info` raises
`ArgumentError` for it and for the other columns Recorder writes itself: `id`,
`item_type`, `item_id`, `event` and `data`.

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
`recorder_enabled!`. That state is cleared when a web request ends, but not
reliably between background jobs, where it would carry over to later jobs on the
same thread; use the block form there.

`Recorder.enabled = false` switches recording off for the whole process, every
thread included, until `Recorder.enabled = true`. It suits a one-off script,
such as a backfill or a data migration; inside a running app it would stop the
trail for every request at once, so use `recorder_disabled!` there. A change is
recorded only while both are on.

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
- `associations` — on `create` and `destroy`, an `attributes` snapshot of each
  association named in `associations:`, filtered by that association's own
  `only:` or `ignore:`. Omitted on `update`, and when no named association is
  set. An associated record's changes are not recorded: they belong to its own
  revisions, and replacing a `belongs_to` target shows up as the foreign key in
  `changes`, unless `only:` or `ignore:` leaves it out.

The snapshot is the contract, not an accident of the implementation: a
revision's `attributes` are self-contained, so reconstructing a record at a
point in time does not mean replaying every prior diff. It is also what keeps a
`destroy` revision useful, since the row it describes is gone. Association
snapshots exist only on `create` and `destroy` revisions.

An `update` records a revision only when the record reports a change; `create`
and `destroy` always record one.

`item_type` holds the model's `polymorphic_name`, the value Active Record
writes to any polymorphic association, so `revisions`, `includes(:revisions)`
and `Recorder::Revision.where(item: record)` all find a record's revisions. For
an STI subclass that is the base class: a `Bond < Instrument` is recorded as
`"Instrument"`, `revision.item` loads it back as a `Bond`, and the subclass name
is in the snapshot's inheritance column (`type` by default) unless `only:` or
`ignore:` leaves it out.

Revisions written before 2.0.0 hold the subclass name, so `revisions` does not
find them. Rewriting them is up to the app; this does it for every subclass
whose class still exists:

```ruby
Recorder::Revision.distinct.pluck(:item_type).each do |type|
  model = type.safe_constantize
  next unless model.respond_to?(:polymorphic_name) && model.polymorphic_name != type

  Recorder::Revision.where(item_type: type).update_all(item_type: model.polymorphic_name)
end
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

Revisions written before 2.0.0 can also hold an association's `changes`,
reachable the same way. `changed_associations` lists the associations that hold
some, and `association_changeset` returns `nil` for one that does not:

```ruby
revision.changed_associations         # ["author"]
revision.association_changeset('author')
```

To render a changeset yourself, define `PostChangeset` — the class is looked up
as `"#{model}Changeset"` — or point at another one with a
`recorder_changeset_class` class method on the model. Otherwise
`Recorder::Changeset` is used.

## Known issues

The gem is under active maintenance and these defects are known:

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
