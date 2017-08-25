$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'

client = Satori::RTM::Client.new(endpoint, appkey)
client.onopen { puts 'Connected to Satori RTM!' }
client.connect

client.subscribe 'zebras', view: "select * from `animals` where `who` = 'zebra'" do |_ctx, event|
  case event.type
  when :subscribed
    puts "Subscribed to: #{event.data[:subscription_id]}"
  when :data
    event.data[:messages].each do |msg|
      puts "Got animal #{msg[:who]}: #{msg}"
    end
  when :error
    puts "Subscription failed #{event.data[:error]}: #{event.data[:reason]}"
  end
end

client.sock_read_repeatedly
