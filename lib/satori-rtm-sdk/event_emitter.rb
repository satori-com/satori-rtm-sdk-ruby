module Satori
  module RTM
    # Event emitter pattern implementation.
    # @!visibility private
    module EventEmitter
      def self.included(klass)
        klass.__send__ :include, InstanceMethods
      end

      # @!visibility private
      module InstanceMethods
        def __handlers
          @__handlers ||= {}
        end

        def on(name, &fn)
          get_handler(name) << fn
          fn
        end

        def fire(name, *args)
          Array.new(get_handler(name)).each do |fn|
            fn.call(*args)
          end

          Array.new(get_handler(:*)).each do |fn|
            fn.call(name, *args)
          end
        end

        private

        def get_handler(name)
          __handlers[name] ||= []
        end
      end
    end
  end
end
