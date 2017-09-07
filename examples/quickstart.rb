$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'satori-rtm-sdk'

endpoint = 'YOUR_ENDPOINT'
appkey = 'YOUR_APPKEY'
# Role and role secret are optional: replace only if you need to authenticate.
role = 'YOUR_ROLE'
role_secret = 'YOUR_SECRET'

# Check if the role is set to authenticate or not
# If an actual role isn't specified, no authentication is needed.
should_authenticate = (role != 'YOUR_ROLE')

puts 'RTM client config:'
puts "\tendpoint = #{endpoint}"
puts "\tappkey = #{appkey}"
if should_authenticate
  puts "\tauthenticate? = true (as #{role})"
else
  puts "\tauthenticate? = false"
end

client = Satori::RTM::Client.new(endpoint, appkey)

# Hook up to client connectivity state transitions
client.onopen do
  puts 'Connected to Satori RTM!'
end

client.onclose do |ev|
  if ev.normal?
    puts 'Satori RTM client is closed normally'
  else
    raise "Satori RTM client is closed abnormally: #{ev.code} -- #{ev.reason}"
  end
end

client.connect

if should_authenticate
  client.authenticate role, role_secret do |reply|
    raise "Failed to authenticate: #{reply.data[:error]} -- #{reply.data[:reason]}" unless reply.success?
  end
  client.wait_all_replies
end

# Subscribe with an event handler
client.subscribe 'animals' do |_ctx, event|
  case event.type
  when :subscribed
    # When the client receives a response from RTM, indicating that the
    # subscription was successful
    puts "Subscribed to the channel: #{event.data[:subscription_id]}"
  when :data
    # When the client receives new messages published to the channel
    event.data[:messages].each { |msg| puts "Animal is received #{msg}" }
  when :error
    # When a subscription error occurs
    puts "Subscription error: #{event.data[:error]} -- #{event.data[:reason]}"
  end
end

# Wait a reply for a subscribe request
client.wait_all_replies

rnd = Random.new

loop do
  # Create a message containing the "location" of an animal
  latitude = 34.13 + (rnd.rand / 100)
  longitude = -118.32 + (rnd.rand / 100)
  animal = { who: 'zebra', where: [latitude, longitude] }

  # Publish the message
  client.publish 'animals', animal do |reply|
    if reply.success?
      puts "Animal is published: #{animal}"
    else
      puts "Failed to publish animal: #{reply.data[:error]} -- #{reply.data[:reason]}"
    end
  end

  # Wait a reply for a publish request
  client.wait_all_replies

  # Read subscription data in a loop from socket for 2 seconds
  client.sock_read_repeatedly duration_in_secs: 2
end
