$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'

client = Satori::RTM::Client.new(endpoint, appkey)

client.connect

client.publish 'animals', who: 'zebra', where: [34.13, -118.32] do |reply|
  if reply.success?
    puts 'Publish confirmed'
  else
    puts "Failed to publish. RTM replied with the error #{reply.data[:error]}: #{reply.data[:reason]}"
  end
end

client.wait_all_replies
