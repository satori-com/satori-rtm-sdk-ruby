$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'
require 'websocket-eventmachine-client'
require 'eventmachine'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'

# WebSocket implementation on top of EventMachine library.
class EventMachineWebSocket
  include Satori::RTM::EventEmitter
  attr_reader :socket

  def connect(url)
    @socket = WebSocket::EventMachine::Client.connect(uri: url)

    @socket.onopen do
      fire :open
    end

    @socket.onmessage do |msg, type|
      fire :message, msg, type
    end

    @socket.onclose do |code, reason|
      fire :close, code, reason
    end
  end

  def close(code = 1000, data = nil)
    @socket.close(code, data)
  end

  def send(data, args)
    type = args[:type] || :text
    case type
    when :text
      @socket.send data
    when :binary
      @socket.send data, type: :binary
    when :ping
      @socket.ping data
    end
  end

  def read_nonblock
    raise NotImplementedError
  end

  def read
    raise NotImplementedError
  end

  def read_with_timeout(_timeout)
    raise NotImplementedError
  end
end

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
end

def message
  rnd = Random.new(Time.now.to_i)
  latitude = 34.13 + (rnd.rand / 100)
  longitude = -118.32 + (rnd.rand / 100)
  { who: 'zebra', where: [latitude, longitude] }
end

def run_publish_loop(client)
  EM.add_periodic_timer 2 do
    client.publish 'animals', message do |reply|
      if reply.success?
        puts "Animal is published: #{message}"
      else
        puts "Failed to publish animal: #{reply.data[:error]} -- #{reply.data[:reason]}"
      end
    end
  end
end

def run_client(endpoint, appkey, state)
  client = Satori::RTM::Client.new(endpoint, appkey, transport: EventMachineWebSocket.new)
  client.connect

  publish_timer = nil
  client.onopen do
    puts 'Connected to Satori RTM!'
    subscribe(client, state)
    publish_timer = run_publish_loop(client)
  end

  client.onclose do
    puts 'Disconnected from Satori RTM!'
    EM.cancel_timer publish_timer if publish_timer
    EM.add_timer(1) do
      run_client(endpoint, appkey, state)
    end
  end
end

EM.run do
  state = {}
  run_client endpoint, appkey, state
end
