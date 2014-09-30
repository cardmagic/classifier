require File.dirname(__FILE__) + '/../test_helper'
class StringExtensionsTest < Test::Unit::TestCase
	def test_word_hash
		hash = {:good=>1, :"!"=>1, :hope=>1, :"'"=>1, :"."=>1, :love=>1, :word=>1, :them=>1, :test=>1}
		assert_equal hash, "here are some good words of test's. I hope you love them!".word_hash
	end
	
	def test_clean_word_hash
	   hash = {:good=>1, :word=>1, :hope=>1, :love=>1, :them=>1, :test=>1}
	   assert_equal hash, "here are some good words of test's. I hope you love them!".clean_word_hash
	end

end

class ArrayExtensionsTest < Test::Unit::TestCase

  def test_plays_nicely_with_any_array
    assert_equal [Array].sum, Array
  end

  def test_monkey_path_array_sum
    assert_equal [1,2,3].sum, 6
  end

  def test_summing_an_empty_array
    assert_equal [nil].sum, 0
  end

  def test_summing_an_empty_array
    assert_equal Array[].sum, 0
  end

end
