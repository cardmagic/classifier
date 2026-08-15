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
    # If a string is passed as an argument, it is automatically treated as a
    # file path and opened. The file will be safely closed immediately after
    # the iteration is complete.
    #
    # @example Reading from multiple files sequentially
    #   log1 = File.open("syslog.log")
    #   log2 = File.open("auth.log")
    #   path = '/var/log/nginx/access.log'
    #
    #   multi = MultiIO.new([log1, log2, path])
    #   multi.each_line do |line|
    #     puts line if line.include?("ERROR")
    #   end
    #
    class MultiIO
      # @rbs @sources: Array[IO | String]

      def initialize(sources)
        @sources = sources.dup
      end

      # @rbs () { (String) -> void } -> void
      # @rbs () -> Enumerator[String, untyped]
      def each_line
        # rubocop:disable Style/ExplicitBlockArgument
        return enum_for(:each_line) unless block_given?

        @sources.each do |source|
          if source.is_a?(String)
            File.open(source) { |io| io.each_line { |line| yield line } }
          else
            source.each_line { |line| yield line }
          end
        end
        # rubocop:enable Style/ExplicitBlockArgument
      end
    end
  end
end
