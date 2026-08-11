# frozen_string_literal: true

require_relative '../test_helper'
require 'stringio'

class MultiIOTest < Minitest::Test
  def test_each_line_returns_enumerator_without_block
    stream = Classifier::Streaming::MultiIO.new(
      [
        StringIO.new("11\n22\n33\n"),
        StringIO.new("44\n55\n66\n"),
        StringIO.new("77\n88\n99\n")
      ]
    )
    enum = stream.each_line

    assert_kind_of Enumerator, enum
    assert_equal "11\n22\n33\n44\n55\n66\n77\n88\n99\n", enum.to_a.join
  end

  def test_each_line_yields_lines_to_block
    stream = Classifier::Streaming::MultiIO.new(
      [
        StringIO.new("11\n22\n"),
        StringIO.new("33\n44\n55\n66\n77\n88\n"),
        StringIO.new("99\n")
      ]
    )
    lines = []
    stream.each_line do |line|
      lines << line.chomp
    end

    assert_equal '112233445566778899', lines.join
  end

  def test_each_line_if_given_path_as_strings
    Dir.mktmpdir do |dir|
      a = File.join(dir, 'a.txt')
      b = File.join(dir, 'b.txt')
      io = StringIO.new("333\n")

      File.write(a, "111\n222\n")
      File.write(b, "444\n")

      stream = Classifier::Streaming::MultiIO.new([a, io, b])

      lines = []
      stream.each_line do |line|
        lines << line.chomp
      end

      assert_equal '111222333444', lines.join
    end
  end
end
