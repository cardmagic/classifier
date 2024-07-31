module GSL
  class Vector
    def _dump(_v)
      Marshal.dump(to_a)
    end

    def self._load(arr)
      arry = Marshal.load(arr)
      GSL::Vector.alloc(arry)
    end
  end

  class Matrix
    class << self
      alias diag diagonal
    end
  end
end
