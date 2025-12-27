require_relative '../test_helper'

class StringExtensionsTest < Minitest::Test
  def test_word_hash
    hash = { good: 1, '!': 1, hope: 1, "'": 1, '.': 1, love: 1, word: 1, them: 1, test: 1 }

    assert_equal hash, "here are some good words of test's. I hope you love them!".word_hash
  end

  def test_clean_word_hash
    hash = { good: 1, word: 1, hope: 1, love: 1, them: 1, test: 1 }

    assert_equal hash, "here are some good words of test's. I hope you love them!".clean_word_hash
  end
end

class ArrayExtensionsTest < Minitest::Test
  def test_monkey_path_array_sum
    assert_equal 6, [1, 2, 3].sum_with_identity
  end

  def test_summing_a_nil_array
    assert_equal 0, [nil].sum_with_identity
  end

  def test_summing_an_empty_array
    assert_equal 0, [].sum_with_identity
  end

  def test_sum_with_block
    assert_in_delta([1, 2, 3].sum_with_identity { |x| x * 2 }, 12.0)
  end

  def test_sum_with_custom_identity
    assert_in_delta([].sum_with_identity(100), 100.0)
  end
end

class StringPunctuationTest < Minitest::Test
  def test_without_punctuation_basic
    result = 'Hello, world!'.without_punctuation

    assert_equal 'Hello  world ', result
  end

  def test_without_punctuation_many_symbols
    result = "Hello (greeting's), with {braces} < >...?".without_punctuation

    assert_equal 'Hello  greetings   with  braces         ', result
  end

  def test_without_punctuation_empty_string
    result = ''.without_punctuation

    assert_equal '', result
  end

  def test_without_punctuation_no_punctuation
    result = 'plain text here'.without_punctuation

    assert_equal 'plain text here', result
  end

  def test_without_punctuation_only_punctuation
    result = "!@\#$%^&*()".without_punctuation

    assert_equal '          ', result
  end
end

class VectorExtensionsTest < Minitest::Test
  def test_magnitude_basic
    vec = Vector[3, 4]

    assert_in_delta 5.0, vec.magnitude, 0.001
  end

  def test_magnitude_zero_vector
    vec = Vector[0, 0, 0]

    assert_in_delta(0.0, vec.magnitude)
  end

  def test_magnitude_single_element
    vec = Vector[5]

    assert_in_delta(5.0, vec.magnitude)
  end

  def test_magnitude_negative_values
    vec = Vector[-3, -4]

    assert_in_delta 5.0, vec.magnitude, 0.001
  end

  def test_normalize_basic
    vec = Vector[3, 4]
    normalized = vec.normalize

    assert_in_delta 1.0, normalized.magnitude, 0.001
  end

  def test_normalize_unit_vector
    vec = Vector[1, 0, 0]
    normalized = vec.normalize

    assert_in_delta 1.0, normalized[0], 0.001
    assert_in_delta 0.0, normalized[1], 0.001
  end

  def test_normalize_preserves_direction
    vec = Vector[2, 0]
    normalized = vec.normalize

    assert_in_delta 1.0, normalized[0], 0.001
    assert_in_delta 0.0, normalized[1], 0.001
  end

  def test_normalize_zero_vector_returns_zero_vector
    vec = Vector[0, 0, 0]
    normalized = vec.normalize

    assert_in_delta 0.0, normalized[0], 0.001
    assert_in_delta 0.0, normalized[1], 0.001
    assert_in_delta 0.0, normalized[2], 0.001
  end

  def test_normalize_near_zero_vector_normalizes_correctly
    # Near-zero vectors should still normalize to unit vectors
    # Only actual zero vectors return zero
    vec = Vector[1e-15, 1e-15, 1e-15]
    normalized = vec.normalize

    # Should normalize to [1/sqrt(3), 1/sqrt(3), 1/sqrt(3)]
    expected = 1.0 / Math.sqrt(3)

    assert_in_delta expected, normalized[0], 0.001
    assert_in_delta expected, normalized[1], 0.001
    assert_in_delta expected, normalized[2], 0.001
  end
end

class MatrixExtensionsTest < Minitest::Test
  def test_diag_creates_diagonal_matrix
    result = Matrix.diag([1, 2, 3])
    expected = Matrix.diagonal(1, 2, 3)

    assert_equal expected, result
  end

  def test_trans_alias
    matrix = Matrix[[1, 2], [3, 4]]

    assert_equal matrix.transpose, matrix.trans
  end

  def test_matrix_element_assignment
    matrix = Matrix[[1, 2], [3, 4]]
    matrix[0, 1] = 99

    assert_equal 99, matrix[0, 1]
  end

  def test_svd_basic
    matrix = Matrix[[1, 0], [0, 1], [0, 0]]
    _u, _v, s = matrix.SV_decomp

    assert_equal 2, s.size
    assert(s.all? { |val| val >= 0 })
  end

  def test_svd_with_zero_rows
    # Matrix with linearly dependent rows that could cause zero singular values
    matrix = Matrix[[1, 1], [1, 1], [0, 0]]
    _u, _v, s = matrix.SV_decomp

    # Should not raise an error
    assert_equal 2, s.size
  end

  def test_svd_handles_near_singular_matrix
    # Near-singular matrix that previously caused Math::DomainError
    matrix = Matrix[[1e-10, 0], [0, 1e-10]]

    # Should not raise an error
    _u, _v, s = matrix.SV_decomp

    assert_equal 2, s.size
  end
end
