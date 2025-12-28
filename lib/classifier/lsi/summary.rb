# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

class String
  ABBREVIATIONS = %w[Mr Mrs Ms Dr Prof Jr Sr Inc Ltd Corp Co vs etc al eg ie].freeze

  def summary(count = 10, separator = ' [...] ')
    perform_lsi split_sentences, count, separator
  end

  def paragraph_summary(count = 1, separator = ' [...] ')
    perform_lsi split_paragraphs, count, separator
  end

  def split_sentences
    return pragmatic_segment if defined?(PragmaticSegmenter)

    split_sentences_regex
  end

  def split_paragraphs
    split(/\r?\n\r?\n+/)
  end

  private

  def pragmatic_segment
    PragmaticSegmenter::Segmenter.new(text: self).segment
  end

  def split_sentences_regex
    abbrev_pattern = ABBREVIATIONS.map { |a| "#{a}\\." }.join('|')
    text = gsub(/\b(#{abbrev_pattern})/i) { |m| m.gsub('.', '<<<DOT>>>') }
    text = text.gsub(/(\d)\.(\d)/, '\1<<<DOT>>>\2')
    sentences = text.split(/(?<=[.!?])(?:\s+|(?=[A-Z]))/)
    sentences.map { |s| s.gsub('<<<DOT>>>', '.') }
  end

  def perform_lsi(chunks, count, separator)
    lsi = Classifier::LSI.new auto_rebuild: false
    chunks.each do |chunk|
      stripped = chunk.strip
      next if stripped.empty? || stripped.split.size == 1

      lsi << chunk
    end
    lsi.build_index
    lsi.highest_relative_content(count).map(&:strip).join(separator)
  end
end
