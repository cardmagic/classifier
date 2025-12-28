# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

require_relative 'base'

module Classifier
  module Storage
    # File-based storage backend.
    #
    # Example:
    #   bayes = Classifier::Bayes.new('Spam', 'Ham')
    #   bayes.storage = Classifier::Storage::File.new(path: "/var/models/spam.json")
    #   bayes.train_spam("Buy now!")
    #   bayes.save
    #
    class File < Base
      # @rbs @path: String

      attr_reader :path

      # @rbs (path: String) -> void
      def initialize(path:)
        @path = path
      end

      # @rbs (String) -> Integer
      def write(data)
        ::File.write(@path, data)
      end

      # @rbs () -> String?
      def read
        exists? ? ::File.read(@path) : nil
      end

      # @rbs () -> void
      def delete
        ::File.delete(@path) if exists?
      end

      # @rbs () -> bool
      def exists?
        ::File.exist?(@path)
      end
    end
  end
end
