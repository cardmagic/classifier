# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

module Classifier
  # Base error class for all Classifier errors
  class Error < StandardError; end

  # Raised when reload would discard unsaved changes
  class UnsavedChangesError < Error; end

  # Raised when a storage operation fails
  class StorageError < Error; end

  # Raised when using an unfitted model
  class NotFittedError < Error; end
end
