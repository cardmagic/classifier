# rbs_inline: enabled

# Author::    Ernest Ellingson
# Copyright:: Copyright (c) 2005

# These are extensions to the std-lib 'matrix' to allow an all ruby SVD

require 'matrix'

# @rbs skip
class Array
  def sum_with_identity(identity = 0.0, &)
    return identity unless size.to_i.positive?
    return map(&).sum_with_identity(identity) if block_given?

    compact.reduce(identity, :+).to_f
  end
end

# @rbs skip
class Vector
  EPSILON = 1e-10

  # Cache magnitude since Vector is immutable after creation
  # Note: We undefine the matrix gem's normalize method first, then redefine it
  # to provide a more robust implementation that handles zero vectors
  undef_method :normalize if method_defined?(:normalize)

  def magnitude
    sum_of_squares = 0.to_r
    size.times do |i|
      sum_of_squares += self[i]**2.to_r
    end
    Math.sqrt(sum_of_squares.to_f)
  end

  def normalize
    magnitude_value = magnitude
    return Vector[*Array.new(size, 0.0)] if magnitude_value <= 0.0

    normalized_values = []
    size.times do |i|
      normalized_values << (self[i] / magnitude_value)
    end
    Vector[*normalized_values]
  end
end

# @rbs skip
class Matrix
  def self.diag(diagonal_elements)
    Matrix.diagonal(*diagonal_elements)
  end

  alias trans transpose

  def SV_decomp(max_sweeps = 20)
    q_matrix = if row_size >= column_size
                 trans * self
               else
                 self * trans
               end

    q_rotation_matrix = q_matrix.dup
    v_matrix = Matrix.identity(q_matrix.row_size)
    iteration_count = 0
    previous_s_matrix = nil

    loop do
      iteration_count += 1
      (0...(q_rotation_matrix.row_size - 1)).each do |row|
        (1..(q_rotation_matrix.row_size - 1)).each do |col|
          next if row == col

          numerator = 2.0 * q_rotation_matrix[row, col]
          denominator = q_rotation_matrix[row, row] - q_rotation_matrix[col, col]

          angle = if denominator.abs < Vector::EPSILON
                    numerator >= 0 ? Math::PI / 4.0 : -Math::PI / 4.0
                  else
                    Math.atan(numerator / denominator) / 2.0
                  end

          cosine = Math.cos(angle)
          sine = Math.sin(angle)
          rotation_matrix = Matrix.identity(q_rotation_matrix.row_size)
          rotation_matrix[row, row] = cosine
          rotation_matrix[row, col] = -sine
          rotation_matrix[col, row] = sine
          rotation_matrix[col, col] = cosine
          q_rotation_matrix = rotation_matrix.trans * q_rotation_matrix * rotation_matrix
          v_matrix *= rotation_matrix
        end
      end
      previous_s_matrix = q_rotation_matrix.dup if iteration_count == 1
      sum_of_differences = 0.to_r
      if iteration_count > 1
        q_rotation_matrix.row_size.times do |r|
          difference = (q_rotation_matrix[r, r] - previous_s_matrix[r, r]).abs
          sum_of_differences += difference.to_r if difference > 0.001
        end
        previous_s_matrix = q_rotation_matrix.dup
      end
      break if (sum_of_differences <= 0.001 && iteration_count > 1) || iteration_count >= max_sweeps
    end

    singular_values = q_rotation_matrix.row_size.times.map do |r|
      Math.sqrt([q_rotation_matrix[r, r].to_f, 0.0].max)
    end

    safe_singular_values = singular_values.map { |v| [v, Vector::EPSILON].max }
    u_matrix = (row_size >= column_size ? self : trans) * v_matrix * Matrix.diagonal(*safe_singular_values).inverse
    [u_matrix, v_matrix, singular_values]
  end

  def []=(row_index, col_index, value)
    @rows[row_index][col_index] = value
  end
end
