# Ruby SDK for Satori RTM

RTM is the realtime messaging service at the core of the [Satori](https://www.satori.com).

Ruby SDK makes it more convenient to use Satori RTM from [Ruby programming language](https://www.ruby-lang.org).

## Installation

Ruby SDK works on Ruby >= 2.0 and JRuby.

Install it with [RubyGems](https://rubygems.org/)

    gem install satori-rtm-sdk --pre

or add this to your Gemfile if you use [Bundler](http://gembundler.com/):

    gem "satori-rtm-sdk", ">= 0.0.1.rc1"

## Documentation

* [Satori Ruby SDK API](https://satori-com.github.io/satori-rtm-sdk-ruby/v0.0.1/)
* [RTM API](https://www.satori.com/docs/using-satori/rtm-api)

## Getting started

Here's an example how to use Satori RTM SDK to write publish / subscribe logic:

```ruby
require 'satori-rtm-sdk'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'

client = Satori::RTM::Client.new(endpoint, appkey)

client.connect

client.subscribe 'animals' do |_ctx, event|
  case event.type
  when :subscribed
    puts "Subscribed to the channel: #{event.data[:subscription_id]}"
  when :data
    event.data[:messages].each { |msg| puts "Animal is received #{msg}" }
  when :error
    puts "Subscription error: #{event.data[:error]} -- #{event.data[:reason]}"
  end
end

loop do
  client.publish 'animals', who: 'zebra', where: [34.13, -118.32]
  client.sock_read_repeatedly duration_in_secs: 2
end
```

## EventMachine

Ruby SDK for Satori RTM doesn't lock you into using threading or event loop frameworks, but it's ready to be used with any of those.

The example of using Ruby SDK with EventMachine can be found in [examples/eventmachine_quickstart.rb](https://github.com/satori-com/satori-rtm-sdk-ruby/blob/master/examples/eventmachine_quickstart.rb)

## Logging

You can enable dumping of all PDUs either from your code

```ruby
Satori::RTM::Logger.use_std_logger(::Logger::DEBUG)
```

or by setting `DEBUG_SATORI_SDK` environment variable prior to running your application

```ruby
$ DEBUG_SATORI_SDK=true ruby myapp.rb
```

## Testing Your Changes

Tests require an active RTM to be available. The tests require `credentials.json` to be populated with the RTM properties.

The `credentials.json` file must include the following key-value pairs:

```
{
  "endpoint": "YOUR_ENDPOINT",
  "appkey": "YOUR_APPKEY",
  "auth_role_name": "YOUR_ROLE",
  "auth_role_secret_key": "YOUR_SECRET",
  "auth_restricted_channel": "YOUR_RESTRICTED_CHANNEL"
}
```

* `endpoint` is your customer-specific endpoint for RTM access.
* `appkey` is your application key.
* `auth_role_name` is a role name that permits to publish / subscribe to `auth_restricted_channel`. Must be not `default`.
* `auth_role_secret_key` is a secret key for `auth_role_name`.
* `auth_restricted_channel` is a channel with subscribe and publish access for `auth_role_name` role only.

After setting up `credentials.json`, just type `rspec spec` at the command line.
