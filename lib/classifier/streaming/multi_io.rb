# frozen_string_literal: true
# rbs_inline: enabled

module Classifier
  module Streaming
    # A utility class that wraps multiple IO-like streams and treats them as a single,
    # sequential stream.
    #
    # `MultiIO` allows you to iterate over lines across multiple input sources
    # (such as files, standard input, or string buffers) seamlessly in the order
    # they are provided.
    #
    # @example Reading from multiple files sequentially
    #   log1 = File.open("syslog.log")
    #   log2 = File.open("auth.log")
    #
    #   multi = MultiIO.new([log1, log2])
    #   multi.each_line do |line|
    #     puts line if line.include?("ERROR")
    #   end
    #
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
