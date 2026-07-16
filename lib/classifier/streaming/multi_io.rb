# rbs_inline: enabled

module Classifier
  module Streaming
    class MultiIO
      # @rbs @streams: Array[IO]

      def initialize(streams)
        @streams = streams.dup
      end

      # @rbs () { (String) -> void } -> void
      # @rbs () -> Enumerator[String, untyped]
      def each_line
        # rubocop:disable Style/ExplicitBlockArgument
        return enum_for(:each_line) unless block_given?

        @streams.each do |stream|
          stream.each_line { |line| yield line }
        end
        # rubocop:enable Style/ExplicitBlockArgument
      end
    end
  end
end
