require 'socket'
require 'openssl'
require 'websocket'

module Satori
  # Satori RTM classes.
  module RTM
    # Error class for any connection related error.
    class ConnectionError < StandardError
    end

    # WebSocket implementation on top of standard TCP sockets.
    class WebSocket
      include EventEmitter
      include Logger

      attr_reader :socket

      def initialize(opts = {})
        @opts = opts
        @state = :none
      end

      def connect(url)
        uri = URI.parse(url)

        @socket = create_socket(uri)
        @socket = start_tls(@socket, uri.host) if uri.scheme == 'wss'

        @hs = ::WebSocket::Handshake::Client.new(url: url)
        @frame = incoming_frame.new(version: @hs.version)

        @state = :open
        do_ws_handshake
        fire :open
      rescue => ex
        close 1006, ex.message
        raise ConnectionError, ex.message, ex.backtrace
      end

      def read_nonblock
        data = nil
        begin
          data = @socket.read_nonblock(1024)
        rescue IO::WaitReadable, IO::WaitWritable
          return :would_block
        end

        @frame << data
        while (frame = @frame.next)
          handle_incoming_frame(frame)
        end
        :ok
      rescue => ex
        close 1006, 'Socket is closed'
        raise ConnectionError, ex.message, ex.backtrace
      end

      def read
        while (rc = read_nonblock) == :would_block
          IO.select([@socket])
        end
        rc
      rescue => ex
        close 1006, 'Socket is closed'
        raise ConnectionError, ex.message, ex.backtrace
      end

      def read_with_timeout(timeout_in_secs)
        now = Time.now
        while (rc = read_nonblock) == :would_block
          diff = Time.now - now
          if timeout_in_secs <= diff
            rc = :timeout
            break
          end
          IO.select([@socket], nil, nil, timeout_in_secs - diff)
        end
        rc
      rescue => ex
        close 1006, 'Socket is closed'
        raise ConnectionError, ex.message, ex.backtrace
      end

      def send(data, args)
        type = args[:type] || :text
        send_frame_unsafe(data, type, args[:code])
      rescue => ex
        close 1006, 'Socket is closed'
        raise ConnectionError, ex.message, ex.backtrace
      end

      def close(code = 1000, reason = nil)
        if @state == :open
          send_frame_unsafe(reason, :close, code)
        elsif @state == :server_close_frame_received
          # server send close frame, replying back with default code
          send_frame_unsafe(reason, :close)
        end
      rescue => ex
        # ignore
        logger.info("fail to close socket: #{ex.message}")
      ensure
        should_trigger_on_close = opened?
        @state = :closed
        @socket.close if @socket
        fire :close, code, reason if should_trigger_on_close
      end

      private

      def opened?
        %i[open server_close_frame_received].include?(@state)
      end

      def incoming_frame
        ::WebSocket::Frame::Incoming::Client
      end

      def outgoing_frame
        ::WebSocket::Frame::Outgoing::Client
      end

      def send_frame_unsafe(data, type = :text, code = nil)
        frame = create_out_frame(data, type, code)
        return if frame.nil?
        @socket.write frame
        @socket.flush
      end

      def handle_incoming_frame(frame)
        case frame.type
        when :close
          @state = :server_close_frame_received
          close frame.code, frame.data
        when :pong
          fire :pong, frame.data
        when :text
          fire :message, frame.data, :text
        end
      end

      def create_socket(uri)
        host = uri.host
        port = uri.port
        port ||= uri.scheme == 'wss' ? 443 : 80
        TCPSocket.new(host, port)
      end

      def start_tls(socket, hostname)
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT

        cert_store = OpenSSL::X509::Store.new
        cert_store.set_default_paths
        ctx.cert_store = cert_store

        ssl_sock = OpenSSL::SSL::SSLSocket.new(socket, ctx)
        # use undocumented method in SSLSocket to make it works with SNI
        ssl_sock.hostname = hostname if ssl_sock.respond_to? :hostname=
        ssl_sock.sync_close = true
        ssl_sock.connect

        ssl_sock
      end

      def do_ws_handshake
        send(@hs.to_s, type: :plain)

        while (line = @socket.gets)
          @hs << line
          break if @hs.finished?
        end

        unless @hs.valid?
          raise ConnectionError, 'handshake error: ' + @hs.error.to_s
        end
      end

      def create_out_frame(data, type, code)
        if type == :plain
          data
        else
          outgoing_frame.new(version: @hs.version, data: data, type: type, code: code).to_s
        end
      end
    end
  end
end
