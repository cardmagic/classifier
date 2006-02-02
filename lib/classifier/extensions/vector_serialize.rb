module GSL
  
  class Vector
    def _dump(v)
      Marshal.dump( self.to_a )
    end
    
    def self._load(arr)
      arry = Marshal.load(arr)
      return GSL::Vector.new(arry)
    end
    
  end
  
  class Matrix
     class <<self
        alias :diag :diagonal
     end
  end
end