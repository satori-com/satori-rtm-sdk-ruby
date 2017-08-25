require 'logger'

module Satori
  module RTM
    # Logger for Satori RTM SDK
    module Logger
      ENV_FLAG = 'DEBUG_SATORI_SDK'.freeze

      class << self
        def create_logger(level, output = $stderr)
          logger = ::Logger.new(output)
          logger.level = level
          logger.progname = 'satori-rtm-sdk'
          logger.formatter = lambda do |severity, datetime, progname, msg|
            formatted_message = case msg
                                when String
                                  msg
                                when Exception
                                  format "%s (%s)\n%s",
                                         msg.message, msg.class, (msg.backtrace || []).join("\n")
                                else
                                  msg.inspect
                                end
            format "%s [%5s] - %s: %s\n",
                   datetime.strftime('%H:%M:%S.%L'),
                   severity,
                   progname,
                   formatted_message
          end
          logger
        end

        # Sets a standard logger for all Satori RTM SDK classes.
        #
        # @param level [Keyword] logger log level
        # @param output [IO] logger output
        # @return [void]
        def use_std_logger(level = default_level, output = $stderr)
          use_logger create_logger(level, output)
        end

        # Sets a logger for all Satori RTM SDK classes.
        #
        # @param value [::Logger] logger
        # @return [void]
        def use_logger(value)
          @global_logger = value
        end

        # Returns current logger
        #
        # @return [::Logger] logger
        def logger
          @global_logger ||= use_std_logger
        end

        # Returns the default logger level
        #
        # @return [Keyword] default logger level
        def default_level
          ENV.key?(ENV_FLAG) ? ::Logger::DEBUG : ::Logger::WARN
        end

        def included(klass)
          klass.__send__ :include, InstanceMethods
        end
      end

      # @!visibility private
      module InstanceMethods
        def logger
          Satori::RTM::Logger.logger
        end
      end
    end
  end
end
