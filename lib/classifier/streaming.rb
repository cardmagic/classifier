# rbs_inline: enabled

require_relative 'streaming/progress'
require_relative 'streaming/line_reader'

module Classifier
  # Streaming module provides memory-efficient training capabilities for classifiers.
  # Include this module in a classifier to add streaming and batch training methods.
  #
  # @example Including in a classifier
  #   class MyClassifier
  #     include Classifier::Streaming
  #   end
  #
  # @example Streaming training
  #   classifier.train_from_stream(:category, File.open('corpus.txt'))
  #
  # @example Batch training with progress
  #   classifier.train_batch(:category, documents, batch_size: 100) do |progress|
  #     puts "#{progress.percent}% complete"
  #   end
  module Streaming
    # Default batch size for streaming operations
    DEFAULT_BATCH_SIZE = 100

    # Trains the classifier from an IO stream.
    # Each line in the stream is treated as a separate document.
    #
    # @rbs (Symbol | String, IO, ?batch_size: Integer) { (Progress) -> void } -> void
    def train_from_stream(category, io, batch_size: DEFAULT_BATCH_SIZE, &block)
      raise NotImplementedError, "#{self.class} must implement train_from_stream"
    end

    # Trains the classifier with an array of documents in batches.
    # Supports both positional and keyword argument styles.
    #
    # @example Positional style
    #   classifier.train_batch(:spam, documents, batch_size: 100)
    #
    # @example Keyword style
    #   classifier.train_batch(spam: documents, ham: other_docs, batch_size: 100)
    #
    # @rbs (?(Symbol | String), ?Array[String], ?batch_size: Integer, **Array[String]) { (Progress) -> void } -> void
    def train_batch(category = nil, documents = nil, batch_size: DEFAULT_BATCH_SIZE, **categories, &block)
      raise NotImplementedError, "#{self.class} must implement train_batch"
    end

    # Saves a checkpoint of the current training state.
    # Requires a storage backend to be configured.
    #
    # @rbs (String) -> void
    def save_checkpoint(checkpoint_id)
      raise ArgumentError, 'No storage configured' unless respond_to?(:storage) && storage

      original_storage = storage

      begin
        self.storage = checkpoint_storage_for(checkpoint_id)
        save
      ensure
        self.storage = original_storage
      end
    end

    # Lists available checkpoints.
    # Requires a storage backend to be configured.
    #
    # @rbs () -> Array[String]
    def list_checkpoints
      raise ArgumentError, 'No storage configured' unless respond_to?(:storage) && storage

      case storage
      when Storage::File
        dir = File.dirname(storage.path)
        base = File.basename(storage.path, '.*')
        ext = File.extname(storage.path)

        pattern = File.join(dir, "#{base}_checkpoint_*#{ext}")
        Dir.glob(pattern).map do |path|
          File.basename(path, ext).sub(/^#{Regexp.escape(base)}_checkpoint_/, '')
        end.sort
      when Storage::Memory
        # Memory storage doesn't support checkpoint listing
        []
      else
        []
      end
    end

    # Deletes a checkpoint.
    #
    # @rbs (String) -> void
    def delete_checkpoint(checkpoint_id)
      raise ArgumentError, 'No storage configured' unless respond_to?(:storage) && storage

      checkpoint_storage = checkpoint_storage_for(checkpoint_id)
      checkpoint_storage.delete if checkpoint_storage.exists?
    end

    private

    # @rbs (String) -> String
    def checkpoint_path_for(checkpoint_id)
      raise ArgumentError, 'Storage must be File storage for checkpoints' unless storage.is_a?(Storage::File)

      dir = File.dirname(storage.path)
      base = File.basename(storage.path, '.*')
      ext = File.extname(storage.path)

      File.join(dir, "#{base}_checkpoint_#{checkpoint_id}#{ext}")
    end

    # @rbs (String) -> Storage::Base
    def checkpoint_storage_for(checkpoint_id)
      case storage
      when Storage::File
        Storage::File.new(path: checkpoint_path_for(checkpoint_id))
      else
        raise ArgumentError, "Checkpoints not supported for #{storage.class}"
      end
    end
  end
end
