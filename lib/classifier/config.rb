# rbs_inline: enabled

module Classifier
  # This lazy initialization is not thread-safe.
  # In multi-threaded environments, ensure this method is called
  # or configuration is set explicitly during startup before using classifiers.
  def config
    @config ||= Config.new
  end

  def configure(&block)
    block.call(config)
  end

  module_function :config, :configure

  class Config
    attr_accessor :min_word_length #: Integer

    def initialize
      @min_word_length = 3
    end
  end
end
