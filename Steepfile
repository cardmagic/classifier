D = Steep::Diagnostic

target :lib do
  signature 'sig'

  check 'lib'

  # Stdlib dependencies for CLI
  library 'fileutils'
  library 'uri'
  library 'net-http'
  library 'json'

  # Strict mode: report methods without type annotations
  configure_code_diagnostics(D::Ruby.strict)

  # Ignore files that patch stdlib classes (these cause conflicts)
  ignore 'lib/classifier/extensions/vector.rb'
  ignore 'lib/classifier/extensions/vector_serialize.rb'
  ignore 'lib/classifier/extensions/string.rb'
  ignore 'lib/classifier/extensions/word_hash.rb'

  # Ignore LSI files for now due to complex GSL/Matrix dual-mode typing
  ignore 'lib/classifier/lsi.rb'
  ignore 'lib/classifier/lsi/content_node.rb'
  ignore 'lib/classifier/lsi/summary.rb'
end
