require_relative '../test_helper'

class StringExtensionsTest < Minitest::Test
  def test_word_hash
    hash = { good: 1, "!": 1, hope: 1, "'": 1, ".": 1, love: 1, word: 1, them: 1, test: 1 }
    assert_equal hash, "here are some good words of test's. I hope you love them!".word_hash
  end

  def test_clean_word_hash
    hash = { good: 1, word: 1, hope: 1, love: 1, them: 1, test: 1 }
    assert_equal hash, "here are some good words of test's. I hope you love them!".clean_word_hash
  end
end

class ArrayExtensionsTest < Minitest::Test
  def test_monkey_path_array_sum
    assert_equal [1, 2, 3].sum_with_identity, 6
  end

  def test_summing_a_nil_array
    assert_equal [nil].sum_with_identity, 0
  end

  def test_summing_an_empty_array
    assert_equal Array[].sum_with_identity, 0
  end
end
