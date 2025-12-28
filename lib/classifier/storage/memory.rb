# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

require_relative 'base'

module Classifier
  module Storage
    # In-memory storage for testing and ephemeral use.
    #
    # Example:
    #   bayes = Classifier::Bayes.new('Spam', 'Ham')
    #   bayes.storage = Classifier::Storage::Memory.new
    #   bayes.train_spam("Buy now!")
    #   bayes.save
    #
    class Memory < Base
      # @rbs @data: String?

      # @rbs () -> void
      def initialize
        @data = nil
      end

      # @rbs (String) -> String
      def write(data)
        @data = data
      end

      # @rbs () -> String?
      def read
        @data
      end

      # @rbs () -> void
      def delete
        @data = nil
      end

      # @rbs () -> bool
      def exists?
        !@data.nil?
      end
    end
  end
end
