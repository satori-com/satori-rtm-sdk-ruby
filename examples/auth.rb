$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'
role = 'YOUR_ROLE'
role_secret = 'YOUR_SECRET'

client = Satori::RTM::Client.new(endpoint, appkey)

client.connect

client.authenticate role, role_secret do |reply|
  if reply.success?
    puts "Connected to Satori RTM and authenticated as #{role}"
  else
    puts "Failed to authenticate: #{reply.data[:error]} -- #{reply.data[:reason]}"
  end
end

client.wait_all_replies
