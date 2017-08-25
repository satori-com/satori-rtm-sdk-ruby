$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'

client = Satori::RTM::Client.new(endpoint, appkey)
client.onopen { puts 'Connected to Satori RTM!' }
client.connect

subscription_handler = proc do |ctx, event|
  case event.type
  when :subscribed
    puts "Subscribed to: #{ctx.subscription_id}"
  when :data
    event.data[:messages].each do |msg|
      if ctx.subscription_id == 'zebras'
        puts "Got a zebra: #{msg}"
      else
        puts "Got a count: #{msg}"
      end
    end
  when :error
    puts "Subscription failed #{event.data[:error]}: #{event.data[:reason]}"
  end
end

client.subscribe 'zebras', view: 'select * from `animals` where `who` = \'zebra\'', &subscription_handler
client.subscribe 'stats', view: 'SELECT count(*) as count, who FROM `animals` GROUP BY who', &subscription_handler

client.sock_read_repeatedly
