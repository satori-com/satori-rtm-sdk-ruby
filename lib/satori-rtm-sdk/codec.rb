require 'json'

module Satori
  module RTM
    # JSON message encoder / decoder.
    # @!visibility private
    class JsonCodec
      def encode(pdu)
        JSON.generate(pdu)
      end

      def decode(data)
        JSON.parse(data, symbolize_names: true)
      end
    end
  end
end
