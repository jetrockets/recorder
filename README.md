# Recorder

Recorder tracks changes of your Rails models

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'recorder'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install recorder

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jetrockets/recorder.

## Credits

![JetRockets](https://media.jetrockets.pro/jetrockets-white.png)

Recorder is maintained by [JetRockets](https://www.jetrockets.pro]).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

