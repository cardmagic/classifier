require_relative '../test_helper'

class SummaryTest < Minitest::Test
  def test_split_sentences_basic
    text = 'Hello world. This is a test. How are you?'
    sentences = text.split_sentences

    assert_equal 3, sentences.size
    assert_equal 'Hello world.', sentences[0]
    assert_equal 'This is a test.', sentences[1]
    assert_equal 'How are you?', sentences[2]
  end

  def test_split_sentences_with_abbreviations
    text = 'Dr. Smith went to the store. He bought milk.'
    sentences = text.split_sentences

    assert_equal 2, sentences.size
    assert_equal 'Dr. Smith went to the store.', sentences[0]
    assert_equal 'He bought milk.', sentences[1]
  end

  def test_split_sentences_with_mr_mrs
    text = 'Mr. Jones met Mrs. Smith. They talked.'
    sentences = text.split_sentences

    assert_equal 2, sentences.size
    assert_equal 'Mr. Jones met Mrs. Smith.', sentences[0]
    assert_equal 'They talked.', sentences[1]
  end

  def test_split_sentences_with_decimals
    text = 'The price is $3.50 per unit. That is expensive.'
    sentences = text.split_sentences

    assert_equal 2, sentences.size
    assert_equal 'The price is $3.50 per unit.', sentences[0]
    assert_equal 'That is expensive.', sentences[1]
  end

  def test_split_sentences_with_exclamation
    text = 'Hello! How are you? I am fine.'
    sentences = text.split_sentences

    assert_equal 3, sentences.size
    assert_equal 'Hello!', sentences[0]
    assert_equal 'How are you?', sentences[1]
    assert_equal 'I am fine.', sentences[2]
  end

  def test_split_sentences_with_inc_corp
    text = 'Apple Inc. makes phones. Microsoft Corp. makes software.'
    sentences = text.split_sentences

    assert_equal 2, sentences.size
    assert_equal 'Apple Inc. makes phones.', sentences[0]
    assert_equal 'Microsoft Corp. makes software.', sentences[1]
  end

  def test_split_sentences_with_etc
    text = 'We need apples, oranges, etc. for the party. Please bring them.'
    sentences = text.split_sentences

    assert_equal 2, sentences.size
    assert_includes sentences[0], 'etc.'
  end

  def test_split_paragraphs_double_newline
    text = "First paragraph.\n\nSecond paragraph."
    paragraphs = text.split_paragraphs

    assert_equal 2, paragraphs.size
    assert_equal 'First paragraph.', paragraphs[0]
    assert_equal 'Second paragraph.', paragraphs[1]
  end

  def test_split_paragraphs_windows_line_endings
    text = "First paragraph.\r\n\r\nSecond paragraph."
    paragraphs = text.split_paragraphs

    assert_equal 2, paragraphs.size
    assert_equal 'First paragraph.', paragraphs[0]
    assert_equal 'Second paragraph.', paragraphs[1]
  end

  def test_split_paragraphs_multiple_newlines
    text = "First paragraph.\n\n\n\nSecond paragraph."
    paragraphs = text.split_paragraphs

    assert_equal 2, paragraphs.size
  end

  def test_split_paragraphs_mixed_line_endings
    text = "First.\r\n\r\nSecond.\n\nThird."
    paragraphs = text.split_paragraphs

    assert_equal 3, paragraphs.size
  end

  def test_summary_returns_string
    text = 'This is sentence one. This is sentence two. This is sentence three.'
    result = text.summary(2)

    assert_instance_of String, result
  end

  def test_paragraph_summary_returns_string
    text = "First paragraph with content.\n\nSecond paragraph with more content."
    result = text.paragraph_summary(1)

    assert_instance_of String, result
  end
end
