require_relative '../test_helper'

# Skip these tests if native extension isn't available
return unless Classifier::LSI.backend == :native

class NativeExtTest < Minitest::Test
  def test_vector_alloc_with_size
    v = Classifier::Linalg::Vector.alloc(5)

    assert_equal 5, v.size
    assert_equal [0.0, 0.0, 0.0, 0.0, 0.0], v.to_a
  end

  def test_vector_alloc_with_array
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0, 3.0])

    assert_equal 3, v.size
    assert_equal [1.0, 2.0, 3.0], v.to_a
  end

  def test_vector_element_access
    v = Classifier::Linalg::Vector.alloc(3)
    v[0] = 1.0
    v[1] = 2.0
    v[2] = 3.0

    assert_in_delta(1.0, v[0])
    assert_in_delta(2.0, v[1])
    assert_in_delta(3.0, v[2])
  end

  def test_vector_sum
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0, 3.0, 4.0])

    assert_in_delta(10.0, v.sum)
  end

  def test_vector_normalize
    v = Classifier::Linalg::Vector.alloc([3.0, 4.0])
    n = v.normalize

    assert_in_delta 0.6, n[0], 0.0001
    assert_in_delta 0.8, n[1], 0.0001
  end

  def test_vector_normalize_zero
    v = Classifier::Linalg::Vector.alloc([0.0, 0.0, 0.0])
    n = v.normalize

    assert_equal [0.0, 0.0, 0.0], n.to_a
  end

  def test_vector_each
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0, 3.0])
    values = []
    v.each { |x| values << x } # rubocop:disable Style/MapIntoArray

    assert_equal [1.0, 2.0, 3.0], values
  end

  def test_vector_collect
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0, 3.0])
    v2 = v.collect { |x| x * 2 }

    assert_equal [2.0, 4.0, 6.0], v2.to_a
  end

  def test_vector_row_col
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0])
    row = v.row
    col = v.col

    assert_equal [1.0, 2.0], row.to_a
    assert_equal [1.0, 2.0], col.to_a
  end

  def test_vector_dot_product
    v1 = Classifier::Linalg::Vector.alloc([1.0, 2.0, 3.0])
    v2 = Classifier::Linalg::Vector.alloc([4.0, 5.0, 6.0])

    assert_in_delta(32.0, v1 * v2)
  end

  def test_vector_scalar_multiply
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0, 3.0])
    v2 = v * 2.0

    assert_equal [2.0, 4.0, 6.0], v2.to_a
  end

  def test_matrix_alloc
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0], [3.0, 4.0])

    assert_equal [2, 2], m.size
    assert_in_delta(1.0, m[0, 0])
    assert_in_delta(2.0, m[0, 1])
    assert_in_delta(3.0, m[1, 0])
    assert_in_delta(4.0, m[1, 1])
  end

  def test_matrix_transpose
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
    t = m.trans

    assert_equal [3, 2], t.size
    assert_equal [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]], t.to_a
  end

  def test_matrix_column
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0], [3.0, 4.0], [5.0, 6.0])
    col = m.column(0)

    assert_equal [1.0, 3.0, 5.0], col.to_a
    col = m.column(1)

    assert_equal [2.0, 4.0, 6.0], col.to_a
  end

  def test_matrix_diag
    m = Classifier::Linalg::Matrix.diag([1.0, 2.0, 3.0])

    assert_equal [3, 3], m.size
    assert_in_delta(1.0, m[0, 0])
    assert_in_delta(2.0, m[1, 1])
    assert_in_delta(3.0, m[2, 2])
    assert_in_delta(0.0, m[0, 1])
  end

  def test_matrix_multiply
    a = Classifier::Linalg::Matrix.alloc([1.0, 2.0], [3.0, 4.0])
    b = Classifier::Linalg::Matrix.alloc([5.0, 6.0], [7.0, 8.0])
    c = a * b

    assert_equal [[19.0, 22.0], [43.0, 50.0]], c.to_a
  end

  def test_matrix_vector_multiply
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0], [3.0, 4.0])
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0])
    result = m * v

    assert_equal [5.0, 11.0], result.to_a
  end

  def test_svd_basic
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0], [3.0, 4.0])
    u, v, s = m.SV_decomp

    # Verify dimensions
    assert_equal 2, s.size

    # Verify reconstruction: A ≈ U * diag(S) * V^T
    s_diag = Classifier::Linalg::Matrix.diag(s.to_a)
    reconstructed = u * s_diag * v.trans

    # Check that reconstruction is close to original
    2.times do |i|
      2.times do |j|
        assert_in_delta m[i, j], reconstructed[i, j], 0.0001,
                        "Element [#{i},#{j}] mismatch in reconstruction"
      end
    end
  end

  def test_svd_rectangular_tall
    # More rows than columns
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0], [3.0, 4.0], [5.0, 6.0])
    _u, _v, s = m.SV_decomp

    assert_equal 2, s.size
  end

  def test_svd_rectangular_wide
    # More columns than rows
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
    _u, _v, s = m.SV_decomp

    assert_equal 2, s.size
  end

  def test_vector_marshal
    v = Classifier::Linalg::Vector.alloc([1.0, 2.0, 3.0])
    dumped = Marshal.dump(v)
    loaded = Marshal.load(dumped)

    assert_equal v.to_a, loaded.to_a
  end

  def test_matrix_marshal
    m = Classifier::Linalg::Matrix.alloc([1.0, 2.0], [3.0, 4.0])
    dumped = Marshal.dump(m)
    loaded = Marshal.load(dumped)

    assert_equal m.to_a, loaded.to_a
  end
end
