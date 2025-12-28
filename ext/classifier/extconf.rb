require 'mkmf'

# Optimization flags for performance
$CFLAGS << ' -O3 -ffast-math -Wall'

# Create the Makefile
create_makefile('classifier/classifier_ext')
