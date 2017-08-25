require 'openssl'
require 'uri'

module Satori
  module RTM
    # The client that an application uses for accessing RTM.
    #
    # @!attribute [r] transport
    #   @return [WebSocket] the WebSocket connection
    class Client
      include EventEmitter
      include Logger

      attr_reader :transport
      private :on, :fire

      # Returns a new instance of Client.
      #
      # @param endpoint [String] RTM endpoint
      # @param appkey [String] appkey used to access RTM
      # @param opts [Hash] options to create a client with.
      # @option opts [WebSocket] :transport WebSocket connection implementation to use
      def initialize(endpoint, appkey, opts = {})
        @waiters = {}
        @subscriptions = {}
        @url = URI.join(endpoint, 'v2?appkey=' + appkey).to_s
        @id = 0
        @encoder = JsonCodec.new
        @transport = init_transport(opts)
        @state = :init
      end

      # @!group I/O

      # Connects to Satori RTM.
      #
      # @raise [ConnectionError] network error occurred when connecting
      # @return [void]
      def connect
        raise ConnectionError, "Client is a single-use object. You can't connect twice." if @state != :init
        logger.info "connecting to #{@url}"
        @transport.connect(@url)
      rescue => e
        # generate websocket close event
        on_websocket_close(1006, "Connect exception: #{e.message}")
        raise e
      end

      # Defines a callback to call when the client is successfully connected to Satori RTM.
      #
      # @yield Calls when client is connected
      # @return [void]
      def onopen(&fn)
        on :open, &fn
      end

      # Defines a callback to call when the client is disconnected or not able to connect to Satori RTM.
      #
      # If a client is not able to connect, a +onclose+ yields too with a reason.
      #
      # @yield Calls when client is disconnected or not able to connect
      # @yieldparam close_event [CloseEvent] reason why client was closed
      # @return [void]
      def onclose(&fn)
        on :close, &fn
      end

      # Returns +true+ if the client is connected.
      #
      # @return [Boolean] +true+ if connected, +false+ otherwise
      def connected?
        @state == :open
      end

      # Closes gracefully the connection to Satori RTM.
      # @return [void]
      def close
        @transport.close
      end

      # Reads from an WebSocket with an optional timeout.
      #
      # If timeout is greater than zero, it specifies a maximum interval (in seconds)
      # to wait for any incoming WebSocket frames. If timeout is zero,
      # then the method returns without blocking. If the timeout is less
      # than zero, the method blocks indefinitely.
      #
      # @param opts [Hash] additional options
      # @option opts [Integer] :timeout_in_secs (-1) timeout for a read operation
      #
      # @raise [ConnectionError] network error occurred when reading data
      # @return [:ok] read successfully reads data from WebSocket
      # @return [:timeout] a blocking operation times out
      def sock_read(opts = {})
        timeout_in_secs = opts.fetch(:timeout_in_secs, -1)
        if timeout_in_secs >= 0
          @transport.read_with_timeout(timeout_in_secs)
        else
          @transport.read
        end
      end

      # Reads from an WebSocket in a non-blocking mode.
      #
      # @raise [ConnectionError] network error occurred when reading data
      # @return [:ok] read successfully reads data from WebSocket
      # @return [:would_block] read buffer is empty
      def sock_read_nonblock
        @transport.read_nonblock
      end

      # Reads repeatedly from an WebSocket.
      #
      # This method repeatedly reads from an WebSocket during a specified
      # time (in seconds). If duration time is greater then zero, then the
      # method blocks for the duration time and reads repeatedly all
      # incoming WebSocket frames. If duration time is less than zero, the
      # method blocks indefinitely.
      #
      # @param opts [Hash] additional options
      # @option opts [Integer] :duration_in_secs (-1) duration interval
      #
      # @raise [ConnectionError] network error occurred when reading data
      # @return [void]
      def sock_read_repeatedly(opts = {})
        duration_in_secs = opts.fetch(:duration_in_secs, -1)
        start = Time.now
        loop do
          diff = (Time.now - start)
          break if (duration_in_secs >= 0) && (duration_in_secs <= diff)
          @transport.read_with_timeout(duration_in_secs - diff)
        end
      end

      # Wait for all RTM replies for all pending requests.
      #
      # This method blocks until all RTM replies are received for all
      # pending requests.
      #
      # If timeout is greater than zero, it specifies a maximum interval (in seconds)
      # to wait for any incoming WebSocket frames.  If the timeout is less
      # than zero, the method blocks indefinitely.
      #
      # @note if user's callback for a reply sends new RTM request
      # then this method waits it too.
      #
      # @param opts [Hash] additional options
      # @option opts [Integer] :timeout_in_secs (-1) timeout for an operation
      #
      # @raise [ConnectionError] network error occurred when reading data
      #
      # @return [:ok] all replies are received
      # @return [:timeout] a blocking operation times out
      def wait_all_replies(opts = {})
        timeout_in_secs = opts.fetch(:timeout_in_secs, -1)
        start = Time.now
        rc = :ok
        loop do
          break if @waiters.empty?

          if timeout_in_secs >= 0
            diff = (Time.now - start)
            if timeout_in_secs <= diff
              rc = :timeout
              break
            end
            @transport.read_with_timeout(timeout_in_secs - diff)
          else
            @transport.read_with_timeout(1)
          end
        end
        rc
      end

      # @!endgroup

      # @!group Satori RTM operations

      # Publishes a message to a channel.
      #
      # @param channel [String] name of the channel
      # @param message [Object] message to publish
      # @yield Callback for an RTM reply. If the block is not given, then
      #   no reply will be sent to a client, regardless of the outcome
      # @yieldparam reply [BaseReply] RTM reply for delete request
      # @return [void]
      def publish(channel, message, &fn)
        publish_opts = {
          channel: channel,
          message: message
        }
        send_r('rtm/publish', publish_opts, &fn)
      end

      # Reads a message in a channel.
      #
      # RTM returns the message at the position specified in the request.
      # If there is no position specified, RTM defaults to the position of
      # the latest message in the channel. A +null+ message in the reply
      # PDU means that there were no messages at that position.
      #
      # @param channel [String] name of the channel
      # @param opts [Hash] additional options for +rtm/read+ request
      # @yield Callback for an RTM reply. If the block is not given, then
      #   no reply will be sent to a client, regardless of the outcome
      # @yieldparam reply [BaseReply] RTM reply for delete request
      # @return [void]
      def read(channel, opts = {}, &fn)
        read_opts = opts.merge channel: channel
        send_r('rtm/read', read_opts, &fn)
      end

      # Writes the value of the specified key from the key-value store.
      #
      # Key is represented by a channel. In current RTM implementation
      # write operation is the same as publish operation.
      #
      # @param channel [String] name of the channel
      # @param message [Object] message to write
      # @yield Callback for an RTM reply. If the block is not given, then
      #   no reply will be sent to a client, regardless of the outcome
      # @yieldparam reply [BaseReply] RTM reply for delete request
      # @return [void]
      def write(channel, message, &fn)
        write_opts = {
          channel: channel,
          message: message
        }
        send_r('rtm/write', write_opts, &fn)
      end

      # Deletes the value of the specified key from the key-value store.
      #
      # Key is represented by a channel, and only the last message in the
      # channel is relevant (represents the value). Hence, publishing a +null+
      # value, serves as deletion of the the previous value (if any). Delete request
      # is the same as publishing or writing a null value to the channel.
      #
      # @param channel [String] name of the channel
      # @yield Callback for an RTM reply. If the block is not given, then
      #   no reply will be sent to a client, regardless of the outcome
      # @yieldparam reply [BaseReply] RTM reply for delete request
      # @return [void]
      def delete(channel, &fn)
        delete_opts = { channel: channel }
        send_r('rtm/delete', delete_opts, &fn)
      end

      # Subscribes to a channel
      #
      # When you create a subscription, you can specify additional subscription options (e.g. history or view).
      # Full list of subscription option you could find in RTM API specification.
      #
      # Satori SDK informs an user about any subscription state changes by calling block with proper event.
      #
      # @see SubscriptionEvent Information about subscription events
      #
      # @param sid [String] subscription id
      # @param opts [Hash] additional options for +rtm/subscribe+ request
      # @yield RTM subscription callback
      # @yieldparam ctx [SubscriptionContext] current subscription context
      # @yieldparam event [SubscriptionEvent] subscription event
      # @return [void]
      #
      # @example
      #   client.subscribe 'animals' do |_ctx, event|
      #     case event.type
      #     when :subscribed
      #       puts "Subscribed to the channel: #{event.data[:subscription_id]}"
      #     when :data
      #       event.data[:messages].each { |msg| puts "Message is received #{msg}" }
      #     when :error
      #       puts "Subscription error: #{event.data[:error]} -- #{event.data[:reason]}"
      #     end
      #   end
      def subscribe(sid, opts = {}, &fn)
        request_opts = opts.merge subscription_id: sid
        request_opts[:channel] = sid unless %i[filter view].any? { |k| opts.key?(k) }

        context = SubscriptionContext.new(sid, opts, fn)

        init_reply = SubscriptionEvent.new(:init, nil)
        context.fn.call(context, init_reply)

        send('rtm/subscribe', request_opts) do |status, data|
          reply = context.handle_data(status, data)

          if @subscriptions.key?(sid) && @subscriptions[sid] != context
            prev_sub = @subscriptions[sid]
            prev_sub.mark_as_resubscribed
          end

          @subscriptions[sid] = context if reply.type == :subscribed

          context.fn.call(context, reply)
        end
      end

      # Unsubscribes the subscription with the specific +subscription_id+
      #
      # @param sid [String] subscription id
      # @yield Callback for an RTM reply
      # @yieldparam reply [BaseReply] RTM reply for authenticate request
      # @return [void]
      def unsubscribe(sid)
        request_opts = { subscription_id: sid }
        send('rtm/unsubscribe', request_opts) do |status, data|
          context = @subscriptions.delete(sid)
          if context
            reply = context.handle_data(status, data)
            context.fn.call(context, reply)
          end
          # pass base reply to unsubscribe block
          yield(BaseReply.new(status, data)) if block_given?
        end
      end

      # Authenticates a user with specific role and secret.
      #
      # Authentication is based on the +HMAC+ algorithm with +MD5+ hashing routine:
      # * The SDK obtains a nonce from the RTM in a handshake request
      # * The SDK then sends an authorization request with its role secret
      #   key hashed with the received nonce
      #
      # If authentication is failed then reason is passed to the yield block. In
      # case of success the +rtm/authenticate+ reply is passed to the yield block.
      #
      # Use Dev Portal to obtain the role and secret key for your application.
      #
      # @param role [String] role name
      # @param secret [String] role secret
      # @yield Callback for an RTM reply
      # @yieldparam reply [BaseReply] RTM reply for authenticate request
      # @return [void]
      #
      # @example
      #   client.authenticate role, role_secret do |reply|
      #     raise "Failed to authenticate: #{reply.data[:error]} -- #{reply.data[:reason]}" unless reply.success?
      #   end
      #   client.wait_all_replies
      def authenticate(role, secret)
        handshake_opts = {
          method: 'role_secret',
          data: { role: role }
        }
        send_r('auth/handshake', handshake_opts) do |reply|
          if reply.success?
            hash = hmac_md5(reply.data[:data][:nonce], secret)
            authenticate_opts = {
              method: 'role_secret',
              credentials: { hash: hash }
            }
            send_r('auth/authenticate', authenticate_opts) do |auth_reply|
              yield(auth_reply)
            end
          else
            yield(reply)
          end
        end
      end

      # @!endgroup

      private

      def pdu_to_reply_adapter(fn)
        return if fn.nil?

        proc do |status, data|
          reply = BaseReply.new(status, data)
          fn.call(reply)
        end
      end

      def send_r(action, body, &fn)
        send(action, body, &pdu_to_reply_adapter(fn))
      end

      def send(action, body, &block)
        pdu = { action: action, body: body }
        if block_given?
          pdu[:id] = gen_next_id
          @waiters[pdu[:id]] = block
        end
        logger.debug("-> #{pdu}")
        data = @encoder.encode(pdu)
        @transport.send(data, type: :text)
      end

      def gen_next_id
        @id += 1
      end

      def on_websocket_open
        logger.info('connection is opened')
        @state = :open
        fire(:open)
      end

      def on_websocket_close(code, reason)
        return if @state == :close
        @state = :close
        is_normal = (code == 1000)
        if is_normal
          logger.info('connection is closed normally')
        else
          logger.warn("connection is closed with code: '#{code}' -- '#{reason}'")
        end

        pass_disconnect_to_all_callbacks

        @waiters = {}
        @subscriptions = {}

        fire(:close, CloseEvent.new(code, reason))
      end

      def pass_disconnect_to_all_callbacks
        err = { error: 'disconnect', reason: 'Connection is closed' }

        @waiters.sort_by(&:first).map do |_, fn|
          safe_call(fn, :disconnect, err)
        end
        @subscriptions.map do |_, context|
          reply = context.handle_data(:disconnect, err)
          safe_call(context.fn, context, reply)
        end
      end

      def on_websocket_message(data, _type)
        pdu = @encoder.decode(data)
        logger.debug("<- #{pdu}")
        id = pdu[:id]
        if id.nil?
          on_unsolicited_pdu(pdu)
        else
          fn = @waiters.delete(id)
          fn.call(:pdu, pdu) unless fn.nil?
        end
      end

      def on_unsolicited_pdu(pdu)
        if pdu[:action] == '/error'
          reason = "Unclassified RTM error is received: #{pdu[:body][:error]} -- #{pdu[:body][:reason]}"
          @transport.close 1008, reason
        elsif pdu[:action].start_with? 'rtm/subscription'
          sid = pdu[:body][:subscription_id]
          context = @subscriptions[sid]
          if context
            reply = context.handle_data(:pdu, pdu)
            context.fn.call(context, reply)
          end
        end
      end

      def hmac_md5(nonce, secret)
        algorithm = OpenSSL::Digest.new('md5')
        digest = OpenSSL::HMAC.digest(algorithm, secret, nonce)
        Base64.encode64(digest).chomp
      end

      def init_transport(opts)
        transport = opts[:transport] || WebSocket.new
        transport.on(:open, &method(:on_websocket_open))
        transport.on(:message, &method(:on_websocket_message))
        transport.on(:close, &method(:on_websocket_close))
        transport
      end

      def safe_call(fn, *args)
        fn.call(*args)
      rescue => e
        logger.error(e)
      end
    end
  end
end
