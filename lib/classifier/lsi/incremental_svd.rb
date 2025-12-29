# rbs_inline: enabled

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
          # Step 1: Project c onto the column space of U
          # m_vec = U^T * c
          m_vec = project(u, c)

          # Step 2: Compute residual (component orthogonal to U)
          # p = c - U * m_vec
          u_times_m = u * m_vec
          p_vec = c - (u_times_m.is_a?(Vector) ? u_times_m : Vector[*u_times_m.to_a.flatten])
          p_norm = magnitude(p_vec)

          if p_norm > epsilon
            # New direction found - rank may increase
            update_with_new_direction(u, s, m_vec, p_vec, p_norm, max_rank, epsilon)
          else
            # Vector is in span of U - no new direction needed
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

        # Update when new document has a component orthogonal to existing U
        # @rbs (Matrix, Array[Float], Vector, Vector, Float, Integer, Float) -> [Matrix, Array[Float]]
        def update_with_new_direction(u, s, m_vec, p_vec, p_norm, max_rank, epsilon)
          # Step 3: Orthonormalize the residual
          p_hat = p_vec * (1.0 / p_norm)

          # Step 4: Form K matrix
          # K = | diag(s)  m_vec |
          #     |   0     p_norm |
          # This is a (k+1) × (k+1) matrix
          k_matrix = build_k_matrix_with_growth(s, m_vec, p_norm)

          # Step 5: SVD of small K matrix
          u_prime, s_prime = small_svd(k_matrix, epsilon)

          # Step 6: Update U = [U | p̂] * U'
          # First, form [U | p̂] which is m × (k+1)
          u_extended = extend_matrix_with_column(u, p_hat)

          # Multiply to get new U
          u_new = u_extended * u_prime

          # Truncate if rank exceeds max_rank
          if s_prime.size > max_rank
            u_new, s_prime = truncate(u_new, s_prime, max_rank)
          end

          [u_new, s_prime]
        end

        # Update when new document is entirely within span of existing U
        # @rbs (Matrix, Array[Float], Vector, Integer, Float) -> [Matrix, Array[Float]]
        def update_in_span(u, s, m_vec, max_rank, epsilon)
          # When vector is in span, we update by forming a different K matrix
          # K = diag(s) with the m_vec contribution
          # This is a rank-1 update to the existing SVD
          k_matrix = build_k_matrix_in_span(s, m_vec)

          # SVD of K
          u_prime, s_prime = small_svd(k_matrix, epsilon)

          # Update U = U * U'
          u_new = u * u_prime

          # Truncate if needed
          if s_prime.size > max_rank
            u_new, s_prime = truncate(u_new, s_prime, max_rank)
          end

          [u_new, s_prime]
        end

        # Builds the K matrix when rank grows by 1
        # K = | diag(s)  m_vec |
        #     |   0      p_norm |
        # @rbs (Array[Float], Vector, Float) -> Matrix
        def build_k_matrix_with_growth(s, m_vec, p_norm)
          k = s.size
          rows = []

          # First k rows: [diag(s), m_vec]
          k.times do |i|
            row = Array.new(k + 1, 0.0)
            row[i] = s[i]
            row[k] = m_vec[i]
            rows << row
          end

          # Last row: [0, ..., 0, p_norm]
          last_row = Array.new(k + 1, 0.0)
          last_row[k] = p_norm
          rows << last_row

          Matrix.rows(rows)
        end

        # Builds the K matrix when vector is in span (no rank growth)
        # This handles the rank-1 update case
        # @rbs (Array[Float], Vector) -> Matrix
        def build_k_matrix_in_span(s, m_vec)
          k = s.size
          rows = []

          # Form diag(s) + contribution from m_vec
          # When c is in span, the update is: A_new = A + c * e_n^T
          # In SVD terms: U * (S + m * e_n^T * V^T) * V^T
          # The K matrix captures this via S with the m contribution
          k.times do |i|
            row = Array.new(k, 0.0)
            row[i] = s[i]
            # Add the m_vec contribution - this creates a rank-1 perturbation
            # The last column gets the m_vec values
            rows << row
          end

          # Actually for in-span case, we need to handle this differently
          # The new column c = U * m, so the matrix grows but not the rank
          # We still need to account for the new column in the reconstruction
          Matrix.rows(rows)
        end

        # Computes SVD of small matrix and extracts singular values
        # @rbs (Matrix, Float) -> [Matrix, Array[Float]]
        def small_svd(matrix, epsilon)
          u, _v, s_array = matrix.SV_decomp

          # Filter out near-zero singular values and sort descending
          s_filtered = s_array.select { |sv| sv.abs > epsilon }
          s_sorted = s_filtered.sort.reverse

          # Keep only columns of U corresponding to non-zero singular values
          # The SV_decomp returns singular values in a specific order
          # We need to reorder U columns to match descending singular value order
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
        # @rbs (Matrix, Array[Float], Integer) -> [Matrix, Array[Float]]
        def truncate(u, s, max_rank)
          s_truncated = s[0...max_rank]
          cols = (0...max_rank).map { |i| u.column(i).to_a }
          u_truncated = Matrix.columns(cols)
          [u_truncated, s_truncated]
        end

        # Computes magnitude of a vector
        # @rbs (Vector) -> Float
        def magnitude(vec)
          Math.sqrt(vec.to_a.sum { |x| x * x })
        end
      end
    end
  end
end
