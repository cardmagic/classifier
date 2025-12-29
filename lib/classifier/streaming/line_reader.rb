# rbs_inline: enabled

module Classifier
  module Streaming
    # Memory-efficient line reader for large files and IO streams.
    # Reads lines one at a time and can yield in configurable batches.
    #
    # @example Reading line by line
    #   reader = LineReader.new(File.open('large_corpus.txt'))
    #   reader.each { |line| process(line) }
    #
    # @example Reading in batches
    #   reader = LineReader.new(io, batch_size: 100)
    #   reader.each_batch { |batch| process_batch(batch) }
    class LineReader
      include Enumerable

      # @rbs @io: IO
      # @rbs @batch_size: Integer

      attr_reader :batch_size

      # Creates a new LineReader.
      #
      # @rbs (IO, ?batch_size: Integer) -> void
      def initialize(io, batch_size: 100)
        @io = io
        @batch_size = batch_size
      end

      # Iterates over each line in the IO stream.
      # Lines are chomped (trailing newlines removed).
      #
      # @rbs () { (String) -> void } -> void
      # @rbs () -> Enumerator[String, void]
      def each(&block)
        return enum_for(:each) unless block_given?

        @io.each_line do |line|
          yield line.chomp
        end
      end

      # Iterates over batches of lines.
      # Each batch is an array of chomped lines.
      #
      # @rbs () { (Array[String]) -> void } -> void
      # @rbs () -> Enumerator[Array[String], void]
      def each_batch
        return enum_for(:each_batch) unless block_given?

        batch = [] #: Array[String]
        each do |line|
          batch << line
          if batch.size >= @batch_size
            yield batch
            batch = []
          end
        end
        yield batch unless batch.empty?
      end

      # Estimates the total number of lines in the IO stream.
      # This is a rough estimate based on file size and average line length.
      # Returns nil for non-seekable streams.
      #
      # @rbs (?sample_size: Integer) -> Integer?
      def estimate_line_count(sample_size: 100)
        return nil unless @io.respond_to?(:size) && @io.respond_to?(:rewind)

        begin
          original_pos = @io.pos
          @io.rewind

          sample_bytes = 0
          sample_lines = 0

          sample_size.times do
            line = @io.gets
            break unless line

            sample_bytes += line.bytesize
            sample_lines += 1
          end

          @io.seek(original_pos)

          return nil if sample_lines.zero?

          avg_line_size = sample_bytes.to_f / sample_lines
          (@io.size / avg_line_size).round
        rescue IOError, Errno::ESPIPE
          nil
        end
      end
    end
  end
end
