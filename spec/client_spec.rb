require 'spec_helper'

describe Satori::RTM::Client do
  before(:each) do
    @client = Satori::RTM::Client.new(endpoint, appkey)
    @events = QueueWithTimeout.new
    @replies = QueueWithTimeout.new

    @client.onopen { @events << [:open] }
    @client.onclose { |ev| @events << [:close, ev] }

    @channel = generate_channel
    @message = { who: 'zebra', where: [1, 2] }
  end

  after(:each) do
    @thread.terminate if @thread
    @thread = nil
    @client.close
  end

  def record_reply(reply)
    @replies << reply
  end

  def connect_and_spawn_reading_thread
    @client.connect
    @thread = Thread.new do
      begin
        loop do
          rc = @client.sock_read timeout_in_secs: 10
          unless %i[ok timeout].include? rc
            pending '`read_with_timeout` returned incorrect code'
          end
        end
      rescue => ex
        puts ex
        puts ex.backtrace
      end
    end
  end

  def close_and_terminate_reading_thread
    @thread.terminate if @thread
    @thread = nil
    @client.close
  end

  it 'should connect, publish and close' do
    connect_and_spawn_reading_thread
    expect(@events.pop).to eq [:open]

    @client.publish(@channel, @message, &method(:record_reply))
    reply = @replies.pop
    expect(reply.success?).to be true
    expect(reply.error?).to be false
    expect(reply.data).to include :position

    close_and_terminate_reading_thread

    (type, close_event) = @events.pop
    expect(type).to eq :close
    expect(close_event.normal?).to eq true
    expect(close_event.code).to eq 1000
  end

  it 'should raise error when publish to closed connection' do
    expect { @client.publish(@channel, @message) }.to raise_error Satori::RTM::ConnectionError

    expect(@client.connected?).to eq false
    connect_and_spawn_reading_thread
    expect(@events.pop).to eq [:open]
    expect(@client.connected?).to eq true

    close_and_terminate_reading_thread

    (type, close_event) = @events.pop
    expect(type).to eq :close
    expect(close_event.normal?).to eq true
    expect(close_event.code).to eq 1000

    expect(@client.connected?).to eq false

    expect { @client.publish(@channel, @message) }.to raise_error Satori::RTM::ConnectionError
    expect(@events.size).to eq 0
  end

  it 'should raise error when closed unexpectedly' do
    @client.connect
    expect(@events.pop).to eq [:open]

    # force close socket unexpectedly on low level
    @client.transport.socket.close
    expect { @client.publish(@channel, @message) }.to raise_error Satori::RTM::ConnectionError

    (type, close_event) = @events.pop
    expect(type).to eq :close
    expect(close_event.code).to eq 1006
    expect(close_event.normal?).to eq false
    expect(close_event.reason).to eq 'Socket is closed'
  end

  context 'authentication' do
    it 'should calculate nonce correctly for authentication' do
      hash = @client.__send__ :hmac_md5, 'nonce', 'B37Ab888CAB4343434bAE98AAAAAABC1'
      expect(hash).to eq 'B510MG+AsMpvUDlm7oFsRg=='
    end

    it 'should authenticate successfully with correct role and secret' do
      connect_and_spawn_reading_thread

      @client.authenticate auth_role_name, auth_role_secret_key, &method(:record_reply)

      reply = @replies.pop
      expect(reply.success?).to be true
    end

    it 'should authenticate unsuccessfully with incorrect secret' do
      connect_and_spawn_reading_thread

      @client.authenticate auth_role_name, 'bad_secret', &method(:record_reply)

      reply = @replies.pop
      expect(reply.success?).to be false
      expect(reply.data[:error]).to eq 'authentication_failed'
    end

    it 'should fail on handshake when role is empty' do
      connect_and_spawn_reading_thread

      @client.authenticate '', 'bad_secret', &method(:record_reply)

      reply = @replies.pop
      expect(reply.success?).to be false
      expect(reply.data[:error]).to eq 'invalid_format'
      expect(reply.data[:reason]).to include '\'role\' must be a non-empty'
    end

    it 'should authenticate and publish' do
      connect_and_spawn_reading_thread

      @client.authenticate auth_role_name, auth_role_secret_key do |reply|
        if reply.success?
          @client.publish auth_restricted_channel, 'message', &method(:record_reply)
        else
          pending 'authenticate is failed'
        end
      end

      reply = @replies.pop
      expect(reply.success?).to be true
      expect(reply.data).to include :position
    end

    it 'should get error when publish to restricted channel' do
      connect_and_spawn_reading_thread

      @client.publish auth_restricted_channel, 'message', &method(:record_reply)

      reply = @replies.pop
      expect(reply.success?).to be false
      expect(reply.error?).to be true
      expect(reply.data[:error]).to eq 'authorization_denied'
    end
  end

  context 'subscription' do
    it 'should publishe and receive json object successfully' do
      connect_and_spawn_reading_thread

      @client.subscribe @channel do |ctx, event|
        case event.type
        when :subscribed
          expect(ctx.state).to be :subscribed
          expect(ctx.position).to eq event.data[:position]
          @client.publish @channel, @message
        when :data
          expect(ctx.state).to be :subscribed
          expect(ctx.position).to eq event.data[:position]
          @replies << event
        end
      end

      reply = @replies.pop

      expect(reply.type).to be :data
      expect(reply.data[:subscription_id]).to eq @channel
      expect(reply.data[:messages]).to eq [@message]
    end

    it 'should subscribe and unsubscribe successfully' do
      connect_and_spawn_reading_thread

      @client.subscribe @channel do |_ctx, event|
        @replies << event.type
      end

      @client.unsubscribe @channel

      expect(@replies.pop).to eq :init
      expect(@replies.pop).to eq :subscribed
      expect(@replies.pop).to eq :unsubscribed
    end

    it 'should unsubscribe with callback when successfully' do
      connect_and_spawn_reading_thread

      @client.subscribe(@channel) {}
      @client.unsubscribe @channel do |reply|
        @replies << reply
      end

      reply = @replies.pop
      expect(reply.success?).to eq true
    end

    it 'should get disconnect event in subscription block after disconnect' do
      @client.connect

      @client.subscribe @channel do |ctx, event|
        @replies << [ctx, event]
      end
      @client.unsubscribe @channel

      (ctx, event) = @replies.pop
      expect(event.type).to eq :init
      expect(ctx.state).to eq :init

      # emulate disconnect
      @client.transport.close

      (ctx, event) = @replies.pop
      expect(ctx.state).to eq :disconnect
      expect(ctx.position).to be_nil
      expect(event.data[:subscription_id]).to eq @channel
      expect(@replies.empty?).to be true
    end

    it 'should unsubscribe after disconnect' do
      @client.connect

      @client.subscribe @channel do |ctx, event|
        @replies << [ctx, event]
      end
      @client.wait_all_replies

      (_ctx, event) = @replies.pop
      expect(event.type).to eq :init

      (_ctx, s_event) = @replies.pop
      expect(s_event.type).to eq :subscribed

      @client.unsubscribe @channel
      @client.transport.close

      (ctx, event) = @replies.pop
      expect(ctx.state).to eq :disconnect
      expect(ctx.position).to eq s_event.data[:position]
      expect(event.data[:subscription_id]).to eq @channel
      expect(@replies.empty?).to be true
    end

    it 'should fail to connect again after close' do
      @client.connect
      @client.close
      expect { @client.connect }.to raise_error Satori::RTM::ConnectionError
    end

    it 'should track position by default an be possible to resubscribe after that later' do
      connect_and_spawn_reading_thread

      # workaround for a bug in RTM when RTM deletes empty channel (should be fixed in next release)
      @client.publish @channel, @message, &method(:record_reply)
      reply = @replies.pop
      expect(reply.success?).to be true

      @client.subscribe @channel do |ctx, event|
        case event.type
        when :subscribed
          @replies << [ctx, event]
        end
      end

      (ctx, reply) = @replies.pop
      expect(ctx.state).to eq :subscribed
      expect(reply.type).to eq :subscribed

      close_and_terminate_reading_thread

      expect(ctx.state).to eq :disconnect
      # check that position in the client is same as position from rtm/subsribe/ok response
      expect(ctx.position).to eq reply.data[:position]

      # reconnect and resubscribe with latest position
      @client = Satori::RTM::Client.new(endpoint, appkey)
      connect_and_spawn_reading_thread

      @client.publish @channel, @message
      @client.subscribe @channel, position: ctx.position do |_ctx, event|
        case event.type
        when :data
          @replies << event
        end
      end

      reply = @replies.pop
      expect(reply.type).to eq :data
      expect(reply.data[:subscription_id]).to eq @channel
      expect(reply.data[:messages]).to eq [@message]
    end

    it 'should subscribes with view successfully' do
      connect_and_spawn_reading_thread

      @client.subscribe @channel, view: "select concat(who,'-view') as name from `#{@channel}`" do |ctx, event|
        case event.type
        when :subscribed
          @client.publish @channel, who: 'zebra'
        when :data
          expect(ctx.state).to be :subscribed
          expect(ctx.position).to eq event.data[:position]
          expect(ctx.subscription_id).to eq @channel
          @replies << event
        end
      end

      reply = @replies.pop
      expect(reply.type).to eq :data
      expect(reply.data[:subscription_id]).to eq @channel
      expect(reply.data[:messages]).to eq [{ name: 'zebra-view' }]
    end

    it 'should handle subscribe error successfully' do
      connect_and_spawn_reading_thread

      @client.subscribe '' do |_ctx, event|
        case event.type
        when :error
          @replies << event
        end
      end

      reply = @replies.pop
      expect(reply.type).to eq :error
      expect(reply.data[:error]).to eq 'invalid_format'
    end

    it 'should handle subscription error successfully' do
      connect_and_spawn_reading_thread

      @client.subscribe @channel do |_ctx, event|
        case event.type
        when :subscribed
          json = JSON.generate(
            action: 'rtm/subscription/error',
            body: {
              subscription_id: @channel,
              error: 'out_of_sync',
              reason: 'Too much traffic'
            }
          )
          @client.transport.fire :message, json, :text
        when :error
          @replies << event
        end
      end

      reply = @replies.pop
      expect(reply.type).to eq :error
      expect(reply.error?).to eq true
      expect(reply.data[:error]).to eq 'out_of_sync'
    end

    it 'should handle subscription info successfully' do
      connect_and_spawn_reading_thread

      @client.subscribe @channel do |_ctx, event|
        case event.type
        when :subscribed
          json = JSON.generate(
            action: 'rtm/subscription/info',
            body: {
              subscription_id: @channel,
              info: 'fast_forward',
              reason: 'Forward',
              missed_message_count: 10
            }
          )
          @client.transport.fire :message, json, :text
        when :info
          @replies << event
        end
      end

      reply = @replies.pop
      expect(reply.type).to eq :info
      expect(reply.data[:info]).to eq 'fast_forward'
      expect(reply.data[:reason]).to eq 'Forward'
      expect(reply.error?).to eq false
      expect(reply.data[:missed_message_count]).to eq 10
    end

    it 'should allow to resubscribe with force flag' do
      connect_and_spawn_reading_thread

      fn = proc do |_ctx, event|
        case event.type
        when :subscribed
          @client.publish @channel, @message
        when :data
          @replies << event
        end
      end

      @client.subscribe @channel, &fn
      reply = @replies.pop
      expect(reply.type).to eq :data
      expect(reply.data[:subscription_id]).to eq @channel
      expect(reply.data[:messages]).to eq [@message]

      @client.subscribe @channel, view: "select concat(who,'-view') as name from `#{@channel}`", force: true, &fn
      reply = @replies.pop
      expect(reply.type).to eq :data
      expect(reply.data[:subscription_id]).to eq @channel
      expect(reply.data[:messages]).to eq [{ name: 'zebra-view' }]
    end
  end

  context 'error handler' do
    it 'should handle system errors from rtm' do
      @client.connect
      expect(@events.pop).to eq [:open]

      json = JSON.generate(
        action: '/error',
        body: {
          error: 'json_parse_error',
          reason: 'JSON is invalid'
        }
      )

      @client.transport.fire :message, json, :text

      (type, close_event) = @events.pop

      expect(type).to eq :close
      expect(close_event.code).to eq 1008
      expect(close_event.reason).to include('json_parse_error')
    end
  end

  context 'message types' do
    it 'should be sent and received correctly' do
      connect_and_spawn_reading_thread

      messages = [
        nil,
        42,
        3.141599999999999,
        'Сообщение',
        [],
        {},
        true,
        false,
        'the last message',
        ['message', nil],
        { key: 'value', key2: nil }
      ]

      @client.subscribe @channel do |_ctx, event|
        case event.type
        when :subscribed
          messages.each { |m| @client.publish @channel, m }
        when :data
          @replies.concat(event.data[:messages])
        end
      end

      messages.each { |m| expect(@replies.pop).to eq m }
    end
  end

  context 'KV operations' do
    it 'performs read / write / delete / read roundtrip' do
      connect_and_spawn_reading_thread
      @client.read @channel, &method(:record_reply)

      reply = @replies.pop
      expect(reply.success?).to be true
      expect(reply.data[:message]).to be nil
      expect(reply.data[:position]).not_to be_nil

      @client.write @channel, @message

      @client.read @channel, &method(:record_reply)

      reply = @replies.pop
      expect(reply.success?).to be true
      expect(reply.data[:message]).to eq @message
      expect(reply.data[:position]).not_to be_nil

      @client.delete @channel, &method(:record_reply)
      reply = @replies.pop
      expect(reply.success?).to be true
      expect(reply.data[:position]).not_to be_nil

      @client.read @channel, &method(:record_reply)

      reply = @replies.pop
      expect(reply.success?).to be true
      expect(reply.data[:message]).to be nil
      expect(reply.data[:position]).not_to be_nil
    end
  end

  context 'on disconnect' do
    it 'the error should be passed to base callback' do
      @client.connect
      @client.publish @channel, @message, &method(:record_reply)
      @client.close

      reply = @replies.pop
      expect(reply.success?).to be false
      expect(reply.data[:error]).to eq 'disconnect'
    end

    it 'the error should be passed to subscription callback' do
      @client.connect
      @client.subscribe @channel do |ctx, event|
        @replies << [ctx, event]
      end

      (ctx, _reply) = @replies.pop
      expect(ctx.position).to be_nil
      expect(ctx.state).to be :init

      @client.wait_all_replies

      (ctx, reply) = @replies.pop

      expect(ctx.state).to eq :subscribed
      expect(ctx.position).to_not be_nil
      expect(ctx.position).to eq reply.data[:position]
      expect(ctx.state).to be :subscribed

      position = String.new(ctx.position)

      @client.close

      (ctx, reply) = @replies.pop

      expect(ctx.position).to eq position
      expect(ctx.state).to be :disconnect
      expect(reply.data[:error]).to eq 'disconnect'
      expect(reply.data[:reason]).to_not be_nil
      expect(reply.data[:subscription_id]).to eq @channel
    end
  end

  context 'server close connection with ws close frame' do
    it 'should pass close code to error callback' do
      @client.connect
      expect(@events.pop).to eq [:open]

      frame = ::WebSocket::Frame::Incoming::Client.new(data: 'rtm_error', type: :close, code: 1003)
      @client.transport.__send__ :handle_incoming_frame, frame

      (type, close_event) = @events.pop

      expect(type).to eq :close
      expect(close_event.code).to eq 1003
      expect(close_event.reason).to include('rtm_error')
    end
  end
end
