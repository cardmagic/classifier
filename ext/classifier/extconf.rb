require 'mkmf'

# rubocop:disable-next Style/GlobalVars
if ENV['COVERAGE']
  # Coverage flags: disable optimization for accurate line coverage
  $CFLAGS << ' -O0 -g --coverage -Wall'
  $LDFLAGS << ' --coverage'
else
  # Optimization flags for performance
  $CFLAGS << ' -O3 -ffast-math -Wall'
end

# Create the Makefile
create_makefile('classifier/classifier_ext')
