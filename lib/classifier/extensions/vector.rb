# Author::    Ernest Ellingson
# Copyright:: Copyright (c) 2005

# These are extensions to the std-lib 'matrix' to allow an all ruby SVD

require 'matrix'

class Array
  def sum_with_identity(identity = 0.0, &block)
    return identity unless size.to_i.positive?
    return map(&block).sum_with_identity(identity) if block_given?

    compact.reduce(:+).to_f || identity.to_f
  end
end

module VectorExtensions
  def magnitude
    sum_of_squares = 0.to_r
    size.times do |i|
      sum_of_squares += self[i]**2.to_r
    end
    Math.sqrt(sum_of_squares.to_f)
  end

  def normalize
    normalized_values = []
    magnitude_value = magnitude.to_r
    size.times do |i|
      normalized_values << (self[i] / magnitude_value)
    end
    Vector[*normalized_values]
  end
end

class Vector
  include VectorExtensions
end

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
      (0...q_rotation_matrix.row_size - 1).each do |row|
        (1..q_rotation_matrix.row_size - 1).each do |col|
          next if row == col

          angle = Math.atan((2.to_r * q_rotation_matrix[row,
                                                        col]) / (q_rotation_matrix[row,
                                                                                   row] - q_rotation_matrix[col,
                                                                                                            col])) / 2.0
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

    singular_values = []
    q_rotation_matrix.row_size.times do |r|
      singular_values << Math.sqrt(q_rotation_matrix[r, r].to_f)
    end
    u_matrix = (row_size >= column_size ? self : trans) * v_matrix * Matrix.diagonal(*singular_values).inverse
    [u_matrix, v_matrix, singular_values]
  end

  def []=(row_index, col_index, value)
    @rows[row_index][col_index] = value
  end
end
