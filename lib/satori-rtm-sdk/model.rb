module Satori
  module RTM
    # Event about new subscription data or subscription status change.
    #
    # @!attribute [r] data
    #   Returns an event data. In most cases it represent +body+ field from incoming
    #   subscribe / subscription / unsubscribe PDUs. The type of PDU is accessible by
    #   +type+ attribute. Information about fields in +data+ could be found in RTM API
    #   specification.
    #   @return [Hash] event data
    #
    # @!attribute [r] type
    #   Returns a type of event.
    #   @return [:init] event before +rtm/subscribe+ request is sent
    #   @return [:subscribed] event when +rtm/subscribe/ok+ is received
    #   @return [:unsubscribed] event when +rtm/unsubscribe/ok+ is received
    #   @return [:error] event when +rtm/subscription/error+ / +rtm/subscribe/error+ are received
    #   @return [:info] event when +rtm/subscription/info+ is received
    #   @return [:disconnect] event when connection is lost
    class SubscriptionEvent
      attr_reader :data, :type

      def initialize(type, data)
        if type == :pdu
          @type = resolve_type(data[:action])
          @data = data[:body]
        else
          @type = type
          @data = data
        end
      end

      # Returns +true+ if event is an error PDU.
      #
      # @return [Boolean] +true+ if event is an error PDU, +false+ otherwise
      def error?
        type == :error
      end

      private

      def resolve_type(action)
        case action
        when 'rtm/subscribe/ok'
          :subscribed
        when 'rtm/unsubscribe/ok'
          :unsubscribed
        when 'rtm/subscription/info'
          :info
        when 'rtm/subscription/data'
          :data
        when 'rtm/subscription/error', 'rtm/subscribe/error', 'rtm/unsubscribe/error'
          :error
        end
      end
    end

    # Base RTM reply for a request.
    #
    # @!attribute [r] data
    #   Returns a reply data. It represent +body+ field from reply PDUs from RTM.
    #   Information about fields in data could be found in RTM API specification.
    #   @return [Hash] event data
    #
    # @!attribute [r] type
    #   Returns a type of reply.
    #   @return [:ok] when RTM positive reply is received
    #   @return [:error] when RTM error is received
    #   @return [:disconnect] when connection is lost
    class BaseReply
      attr_reader :data, :type

      def initialize(type, data)
        if type == :pdu
          @type = data[:action].end_with?('/ok') ? :ok : :error
          @data = data[:body]
        else
          @type = type
          @data = data
        end
      end

      # Returns +true+ if a reply is positive
      #
      # @return [Boolean] +true+ if a reply is positive, +false+ otherwise
      def success?
        type == :ok
      end

      # Returns +true+ if a reply is not positive
      #
      # @return [Boolean] +true+ if a reply is not positive, +false+ otherwise
      def error?
        !success?
      end
    end

    # Close event with information why connection is closed or can't be established.
    #
    # @!attribute [r] code
    #   Returns a WebSocket close frame code
    #   @see https://tools.ietf.org/html/rfc6455 WebSocket RFC
    #   @return [Number] close code
    #
    # @!attribute [r] reason
    #   Returns a human-readable reason why connection is closed or can't be established.
    #   @return [String] close reason
    class CloseEvent
      attr_reader :code, :reason

      def initialize(code, reason)
        @code = code
        @reason = reason
      end

      # Returns +true+ if connection was closed normally
      # @return [Boolean] +true+ if connection was closed normally, +false+ otherwise
      def normal?
        @code == 1000
      end
    end

    # Context with initial subscription settings and current subscription state.
    #
    # @!attribute [r] subscription_id
    #   @return [String] subscription identifier
    #
    # @!attribute [r] req_opts
    #   @return [Hash] additional options for +rtm/subscribe+ request used to create the subscription
    #
    # @!attribute [r] fn
    #   @return [Proc] RTM subscription yield block used to create the subscription
    #
    # @!attribute [r] position
    #   @return [String] current subscription position. Updated automatically after each RTM reply
    #
    # @!attribute [r] state
    #   Subscription state
    #   @return [:init] not established
    #   @return [:subscribed] subscribed
    #   @return [:unsubscribed] unsubscribed with +rtm/unsubscribe+ request
    #   @return [:disconnect] unsubscribed because connection is lost
    #   @return [:resubscribed] unsubscribed because new subscription replaces it with +force+ flag
    class SubscriptionContext
      attr_reader :subscription_id, :req_opts, :fn, :position, :state

      def initialize(sid, opts, fn)
        raise ArgumentError, 'subscription callback function should be specified' if fn.nil?

        @subscription_id = sid
        @fn = fn
        @req_opts = opts
        @position = nil
        @state = :init
      end

      # @!visibility private
      def handle_data(status, data)
        data[:subscription_id] = @subscription_id if status == :disconnect
        reply = SubscriptionEvent.new(status, data)
        handle_reply(reply)
        reply
      end

      # @!visibility private
      def handle_reply(reply)
        @position = reply.data[:position] if reply.data.key?(:position)
        case reply.type
        when :subscribed, :unsubscribed, :error, :disconnect
          @state = reply.type
        end
      end

      # @!visibility private
      def mark_as_resubscribed
        @state = :resubscribed
      end
    end
  end
end
