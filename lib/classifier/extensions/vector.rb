# Author::    Ernest Ellingson
# Copyright:: Copyright (c) 2005 

# These are extensions to the std-lib 'matrix' to allow an all ruby SVD

require 'matrix'
require 'mathn'

class Array
  def sum(identity = 0, &block)
    return identity unless size > 0
  
    if block_given?
      map(&block).sum
    else
      inject { |sum, element| sum + element }.to_f
    end
  end
end

class Vector
  def magnitude
    sumsqs = 0.0
    self.size.times do |i|
      sumsqs += self[i] ** 2.0 
    end
    Math.sqrt(sumsqs)
  end
  def normalize
    nv = []
    mag = self.magnitude
    self.size.times do |i|

      nv << (self[i] / mag)

    end
    Vector[*nv]
  end
end

class Matrix
  def Matrix.diag(s)
     Matrix.diagonal(*s)
  end
  
  alias :trans :transpose

  def SV_decomp(maxSweeps = 20)
    if self.row_size >= self.column_size
      q = self.trans * self
    else
      q = self * self.trans
    end
    
    qrot    = q.dup
    v       = Matrix.identity(q.row_size)
    azrot   = nil
    mzrot   = nil
    cnt     = 0
    s_old   = nil
    mu      = nil

    while true do
      cnt += 1
      for row in (0...qrot.row_size-1) do
        for col in (1..qrot.row_size-1) do
          next if row == col
          h = Math.atan((2 * qrot[row,col])/(qrot[row,row]-qrot[col,col]))/2.0
          hcos = Math.cos(h)
          hsin = Math.sin(h)
          mzrot = Matrix.identity(qrot.row_size)
          mzrot[row,row] = hcos
          mzrot[row,col] = -hsin
          mzrot[col,row] = hsin
          mzrot[col,col] = hcos
          qrot = mzrot.trans * qrot * mzrot
          v = v * mzrot
        end 
      end
      s_old = qrot.dup if cnt == 1
      sum_qrot = 0.0 
      if cnt > 1
        qrot.row_size.times do |r|
          sum_qrot += (qrot[r,r]-s_old[r,r]).abs if (qrot[r,r]-s_old[r,r]).abs > 0.001
        end
        s_old = qrot.dup
      end 
      break if (sum_qrot <= 0.001 and cnt > 1) or cnt >= maxSweeps
    end # of do while true
    s = []
    qrot.row_size.times do |r|
      s << Math.sqrt(qrot[r,r])
    end
    #puts "cnt = #{cnt}"
    if self.row_size >= self.column_size
      mu = self *  v * Matrix.diagonal(*s).inverse     
      return [mu, v, s]
    else
      puts v.row_size
      puts v.column_size
      puts self.row_size
      puts self.column_size
      puts s.size

      mu = (self.trans * v *  Matrix.diagonal(*s).inverse)
      return [mu, v, s]
    end
  end
  def []=(i,j,val)
    @rows[i][j] = val
  end
end
