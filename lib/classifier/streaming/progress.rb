# rbs_inline: enabled

module Classifier
  module Streaming
    # Progress tracking object yielded to blocks during batch/stream operations.
    # Provides information about training progress including completion percentage,
    # elapsed time, processing rate, and estimated time remaining.
    #
    # @example Basic usage with train_batch
    #   classifier.train_batch(:spam, documents, batch_size: 100) do |progress|
    #     puts "#{progress.completed}/#{progress.total} (#{progress.percent}%)"
    #     puts "Rate: #{progress.rate.round(1)} docs/sec"
    #     puts "ETA: #{progress.eta&.round}s" if progress.eta
    #   end
    class Progress
      # @rbs @completed: Integer
      # @rbs @total: Integer?
      # @rbs @start_time: Time
      # @rbs @current_batch: Integer

      attr_reader :start_time, :total
      attr_accessor :completed, :current_batch

      # @rbs (?total: Integer?, ?completed: Integer) -> void
      def initialize(total: nil, completed: 0)
        @completed = completed
        @total = total
        @start_time = Time.now
        @current_batch = 0
      end

      # Returns the completion percentage (0-100).
      # Returns nil if total is unknown.
      #
      # @rbs () -> Float?
      def percent
        return nil unless @total && @total.positive?

        (@completed.to_f / @total * 100).round(2)
      end

      # Returns the elapsed time in seconds since the operation started.
      #
      # @rbs () -> Float
      def elapsed
        Time.now - @start_time
      end

      # Returns the processing rate in items per second.
      # Returns 0 if no time has elapsed.
      #
      # @rbs () -> Float
      def rate
        e = elapsed
        return 0.0 if e.zero?

        @completed / e
      end

      # Returns the estimated time remaining in seconds.
      # Returns nil if total is unknown or rate is zero.
      #
      # @rbs () -> Float?
      def eta
        return nil unless @total
        return nil if rate.zero?
        return 0.0 if @completed >= @total

        (@total - @completed) / rate
      end

      # Returns true if the operation is complete.
      #
      # @rbs () -> bool
      def complete?
        return false unless @total

        @completed >= @total
      end

      # Returns a hash representation of the progress state.
      #
      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        {
          completed: @completed,
          total: @total,
          percent: percent,
          elapsed: elapsed.round(2),
          rate: rate.round(2),
          eta: eta&.round(2)
        }
      end
    end
  end
end
