$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'

endpoint = 'wss://open-data.api.satori.com'
appkey = 'YOUR_APPKEY'
channel = 'YOUR_CHANNEL'

client = Satori::RTM::Client.new(endpoint, appkey)
client.onopen { puts 'Connected to Satori RTM!' }
client.connect

client.subscribe channel do |_ctx, event|
  case event.type
  when :data
    event.data[:messages].each do |msg|
      puts "Got message: #{msg}"
    end
  end
end

client.sock_read_repeatedly
