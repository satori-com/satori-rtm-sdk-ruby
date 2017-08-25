$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'

def error_recover(client, ctx, event)
  case event.data[:error]
  when 'expired_position', 'out_of_sync'
    # drop position and subscribe again
    opts = ctx.req_opts.merge position: nil
    client.subscribe ctx.subscription_id, opts, &ctx.fn
  else
    puts "Subscription error: #{event.data[:error]} -- #{event.data[:reason]}"
  end
end

def subscribe_fn(client, state)
  proc do |ctx, event|
    case event.type
    when :init
      state[ctx.subscription_id] = ctx
    when :subscribed
      puts "Subscribed to the channel: #{event.data[:subscription_id]}"
    when :data
      event.data[:messages].each { |msg| puts "Animal is received #{msg}" }
    when :error
      error_recover(client, ctx, event)
    end
  end
end

def subscribe(client, state)
  channel = 'animals'
  position = state[channel] ? state[channel].position : nil
  client.subscribe channel, position: position, &subscribe_fn(client, state)
  client.wait_all_replies
end

def message
  rnd = Random.new(Time.now.to_i)
  latitude = 34.13 + (rnd.rand / 100)
  longitude = -118.32 + (rnd.rand / 100)
  { who: 'zebra', where: [latitude, longitude] }
end

def publish(client)
  loop do
    client.publish 'animals', message do |reply|
      if reply.success?
        puts "Animal is published: #{message}"
      else
        puts "Failed to publish animal: #{reply.data[:error]} -- #{reply.data[:reason]}"
      end
    end
    client.wait_all_replies

    client.sock_read_repeatedly duration_in_secs: 2
    client.transport.close
  end
end

def run_client(endpoint, appkey, state)
  client = Satori::RTM::Client.new(endpoint, appkey)
  client.connect

  subscribe(client, state)
  publish(client)
end

state = {}
loop do
  begin
    run_client endpoint, appkey, state
  rescue Satori::RTM::ConnectionError => ex
    puts "Connection is closed: #{ex}"
    puts ex.backtrace
    sleep 5
  rescue
    raise
  end
end
