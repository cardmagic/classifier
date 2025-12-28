# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

module Classifier
  module Storage
    # Abstract base class for storage backends.
    # Implement this protocol to create custom storage (Redis, PostgreSQL, etc.)
    #
    # Example:
    #   class RedisStorage < Classifier::Storage::Base
    #     def initialize(redis:, key:)
    #       @redis, @key = redis, key
    #     end
    #
    #     def write(data) = @redis.set(@key, data)
    #     def read = @redis.get(@key)
    #     def delete = @redis.del(@key)
    #     def exists? = @redis.exists?(@key)
    #   end
    #
    class Base
      # Save classifier data
      # @rbs (String) -> void
      def write(data)
        raise NotImplementedError, "#{self.class}#write must be implemented"
      end

      # Load classifier data
      # @rbs () -> String?
      def read
        raise NotImplementedError, "#{self.class}#read must be implemented"
      end

      # Delete classifier data
      # @rbs () -> void
      def delete
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end

      # Check if data exists
      # @rbs () -> bool
      def exists?
        raise NotImplementedError, "#{self.class}#exists? must be implemented"
      end
    end
  end
end
