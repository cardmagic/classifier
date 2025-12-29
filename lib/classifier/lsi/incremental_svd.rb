# rbs_inline: enabled

# rubocop:disable Naming/MethodParameterName, Metrics/ParameterLists

require 'matrix'

module Classifier
  class LSI
    # Brand's Incremental SVD Algorithm for LSI
    #
    # Implements the algorithm from Brand (2006) "Fast low-rank modifications
    # of the thin singular value decomposition" for adding documents to LSI
    # without full SVD recomputation.
    #
    # Given existing thin SVD: A ≈ U * S * V^T (with k components)
    # When adding a new column c:
    #
    # 1. Project: m = U^T * c (project onto existing column space)
    # 2. Residual: p = c - U * m (component orthogonal to U)
    # 3. Orthonormalize: If ||p|| > ε: p̂ = p / ||p||
    # 4. Form K matrix:
    #    - If ||p|| > ε: K = [diag(s), m; 0, ||p||] (rank grows by 1)
    #    - If ||p|| ≈ 0: K = diag(s) + m * e_last^T (no new direction)
    # 5. Small SVD: Compute SVD of K (only (k+1) × (k+1) matrix!)
    # 6. Update:
    #    - U_new = [U, p̂] * U'
    #    - S_new = S'
    #
    module IncrementalSVD
      EPSILON = 1e-10

      class << self
        # Updates SVD with a new document vector using Brand's algorithm.
        #
        # @param u [Matrix] current left singular vectors (m × k)
        # @param s [Array<Float>] current singular values (k values)
        # @param c [Vector] new document vector (m × 1)
        # @param max_rank [Integer] maximum rank to maintain
        # @param epsilon [Float] threshold for zero detection
        # @return [Array<Matrix, Array<Float>>] updated [u, s]
        #
        # @rbs (Matrix, Array[Float], Vector, max_rank: Integer, ?epsilon: Float) -> [Matrix, Array[Float]]
        def update(u, s, c, max_rank:, epsilon: EPSILON)
          m_vec = project(u, c)
          u_times_m = u * m_vec
          p_vec = c - (u_times_m.is_a?(Vector) ? u_times_m : Vector[*u_times_m.to_a.flatten])
          p_norm = magnitude(p_vec)

          if p_norm > epsilon
            update_with_new_direction(u, s, m_vec, p_vec, p_norm, max_rank, epsilon)
          else
            update_in_span(u, s, m_vec, max_rank, epsilon)
          end
        end

        # Projects a document vector onto the semantic space defined by U.
        # Returns the LSI representation: lsi_vec = U^T * raw_vec
        #
        # @param u [Matrix] left singular vectors (m × k)
        # @param raw_vec [Vector] document vector in term space (m × 1)
        # @return [Vector] document in semantic space (k × 1)
        #
        # @rbs (Matrix, Vector) -> Vector
        def project(u, raw_vec)
          result = u.transpose * raw_vec
          result.is_a?(Vector) ? result : Vector[*result.to_a.flatten]
        end

        private

        # Update when new document has a component orthogonal to existing U.
        # @rbs (Matrix, Array[Float], Vector, Vector, Float, Integer, Float) -> [Matrix, Array[Float]]
        def update_with_new_direction(u, s, m_vec, p_vec, p_norm, max_rank, epsilon)
          p_hat = p_vec * (1.0 / p_norm)
          k_matrix = build_k_matrix_with_growth(s, m_vec, p_norm)
          u_prime, s_prime = small_svd(k_matrix, epsilon)
          u_extended = extend_matrix_with_column(u, p_hat)
          u_new = u_extended * u_prime

          u_new, s_prime = truncate(u_new, s_prime, max_rank) if s_prime.size > max_rank

          [u_new, s_prime]
        end

        # Update when new document is entirely within span of existing U.
        # @rbs (Matrix, Array[Float], Vector, Integer, Float) -> [Matrix, Array[Float]]
        def update_in_span(u, s, m_vec, max_rank, epsilon)
          k_matrix = build_k_matrix_in_span(s, m_vec)
          u_prime, s_prime = small_svd(k_matrix, epsilon)
          u_new = u * u_prime

          u_new, s_prime = truncate(u_new, s_prime, max_rank) if s_prime.size > max_rank

          [u_new, s_prime]
        end

        # Builds the K matrix when rank grows by 1.
        # @rbs (Array[Float], untyped, Float) -> untyped
        def build_k_matrix_with_growth(s, m_vec, p_norm)
          k = s.size
          rows = k.times.map do |i|
            row = Array.new(k + 1, 0.0) #: Array[Float]
            row[i] = s[i].to_f
            row[k] = m_vec[i].to_f
            row
          end
          rows << Array.new(k + 1, 0.0).tap { |r| r[k] = p_norm }
          Matrix.rows(rows)
        end

        # Builds the K matrix when vector is in span (no rank growth).
        # @rbs (Array[Float], Vector) -> Matrix
        def build_k_matrix_in_span(s, _m_vec)
          k = s.size
          rows = k.times.map do |i|
            row = Array.new(k, 0.0)
            row[i] = s[i]
            row
          end
          Matrix.rows(rows)
        end

        # Computes SVD of small matrix and extracts singular values.
        # @rbs (Matrix, Float) -> [Matrix, Array[Float]]
        def small_svd(matrix, epsilon)
          u, _v, s_array = matrix.SV_decomp

          s_sorted = s_array.select { |sv| sv.abs > epsilon }.sort.reverse
          indices = s_array.each_with_index
                           .select { |sv, _| sv.abs > epsilon }
                           .sort_by { |sv, _| -sv }
                           .map { |_, i| i }

          u_cols = indices.map { |i| u.column(i).to_a }
          u_reordered = u_cols.empty? ? Matrix.empty(matrix.row_size, 0) : Matrix.columns(u_cols)

          [u_reordered, s_sorted]
        end

        # Extends matrix with a new column
        # @rbs (Matrix, Vector) -> Matrix
        def extend_matrix_with_column(matrix, col_vec)
          rows = matrix.row_size.times.map do |i|
            matrix.row(i).to_a + [col_vec[i]]
          end
          Matrix.rows(rows)
        end

        # Truncates to max_rank
        # @rbs (untyped, Array[Float], Integer) -> [untyped, Array[Float]]
        def truncate(u, s, max_rank)
          s_truncated = s[0...max_rank] || [] #: Array[Float]
          cols = (0...max_rank).map { |i| u.column(i).to_a }
          u_truncated = Matrix.columns(cols)
          [u_truncated, s_truncated]
        end

        # Computes magnitude of a vector
        # @rbs (untyped) -> Float
        def magnitude(vec)
          Math.sqrt(vec.to_a.sum { |x| x.to_f * x.to_f })
        end
      end
    end
  end
end
# rubocop:enable Naming/MethodParameterName, Metrics/ParameterLists
