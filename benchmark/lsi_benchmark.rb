#!/usr/bin/env ruby
# frozen_string_literal: true

# LSI Benchmark Script
# Compares performance with and without GSL
#
# Usage:
#   rake benchmark               # Run with current configuration
#   rake benchmark:compare       # Run both GSL and native, show comparison
#   NATIVE_VECTOR=true rake benchmark  # Force native Ruby mode
#
# Note: The native Ruby SVD implementation may fail with larger document sets
# due to numerical instability (Math::DomainError). GSL is recommended for
# production use with large document collections.

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'benchmark'

# Sample documents matching the pattern used in tests (short with repeated keywords)
CATEGORIES = {
  dog: [
    'This text deals with dogs. Dogs.',
    'This text involves dogs too. Dogs!',
    'Dogs are great pets. Dogs are loyal.',
    'I love dogs very much. Dogs!'
  ],
  cat: [
    'This text revolves around cats. Cats.',
    'This text also involves cats. Cats!',
    'Cats are independent pets. Cats.',
    'I enjoy cats very much. Cats!'
  ],
  bird: [
    'This text involves birds. Birds.',
    'Birds can fly high. Birds!',
    'Many birds sing songs. Birds.',
    'I watch birds often. Birds!'
  ],
  fish: [
    'This text is about fish. Fish.',
    'Fish swim in water. Fish!',
    'Tropical fish are colorful. Fish.',
    'I keep fish as pets. Fish!'
  ],
  horse: [
    'This text discusses horses. Horses.',
    'Horses run very fast. Horses!',
    'Wild horses are free. Horses.',
    'I ride horses often. Horses!'
  ]
}.freeze

def generate_documents(count)
  docs = []
  categories = CATEGORIES.keys

  count.times do |i|
    category = categories[i % categories.size]
    base_texts = CATEGORIES[category]
    text = base_texts[i % base_texts.size]
    docs << ["#{text} Number #{i}.", category]
  end
  docs
end

def run_benchmark(doc_count)
  require 'classifier'

  gsl_status = Classifier::LSI.gsl_available ? 'GSL' : 'Native Ruby'
  docs = generate_documents(doc_count)

  puts "\n#{'=' * 60}"
  puts "LSI Benchmark: #{doc_count} documents (#{gsl_status})"
  puts '=' * 60

  results = {}

  begin
    # Benchmark: Adding items (without auto-rebuild)
    lsi = nil
    results[:add_items] = Benchmark.measure do
      lsi = Classifier::LSI.new(auto_rebuild: false)
      docs.each { |doc, category| lsi.add_item(doc, category) }
    end

    # Benchmark: Building index
    results[:build_index] = Benchmark.measure do
      lsi.build_index
    end

    # Benchmark: Classification (100 iterations)
    test_doc = 'This is about dogs. Dogs!'
    results[:classify] = Benchmark.measure do
      100.times { lsi.classify(test_doc) }
    end

    # Benchmark: Search (100 iterations)
    results[:search] = Benchmark.measure do
      100.times { lsi.search('dogs pets', 5) }
    end

    # Benchmark: Find related (100 iterations)
    sample_doc = docs.first[0]
    results[:find_related] = Benchmark.measure do
      100.times { lsi.find_related(sample_doc, 5) }
    end

    # Print results
    puts "\n%-20s %10s %10s %10s" % ['Operation', 'User', 'System', 'Total']
    puts '-' * 52
    results.each do |name, bm|
      puts "%-20s %10.4f %10.4f %10.4f" % [name, bm.utime, bm.stime, bm.total]
    end

    total = results.values.sum(&:total)
    puts '-' * 52
    puts "%-20s %10s %10s %10.4f" % ['TOTAL', '', '', total]

    { results: results, gsl: Classifier::LSI.gsl_available, success: true }
  rescue Math::DomainError => e
    puts "\nFAILED: Native Ruby SVD numerical instability"
    puts "Error: #{e.message}"
    puts "Tip: Install GSL for stable large-scale benchmarks: gem install gsl"
    { results: {}, gsl: false, success: false, error: e.message }
  end
end

def run_single
  sizes = [10, 20, 50, 100]
  failed = false

  sizes.each do |size|
    result = run_benchmark(size)
    if !result[:success]
      failed = true
      break
    end
  end

  if failed
    puts "\n" + '=' * 60
    puts "Note: Native Ruby SVD has numerical stability limits."
    puts "For larger benchmarks, install GSL: gem install gsl"
  end
end

def run_comparison
  sizes = [10, 20, 50]

  puts "#{'#' * 70}"
  puts '# LSI BENCHMARK: GSL vs Native Ruby Comparison'
  puts "#{'#' * 70}"

  native_results = {}
  gsl_results = {}

  # Generate documents once for consistency
  doc_sets = sizes.map { |s| [s, generate_documents(s)] }.to_h

  # Run native benchmarks in subprocess
  puts "\n>>> Running Native Ruby benchmarks..."
  sizes.each do |size|
    docs = doc_sets[size]
    docs_literal = docs.map { |d, c| "[#{d.inspect}, #{c.inspect}]" }.join(', ')

    io = IO.popen([
      RbConfig.ruby,
      '-I', File.expand_path('../lib', __dir__),
      '-e', <<~RUBY
        ENV['NATIVE_VECTOR'] = 'true'
        ENV['SUPPRESS_GSL_WARNING'] = 'true'
        require 'benchmark'
        require 'classifier'

        docs = [#{docs_literal}]
        lsi = Classifier::LSI.new(auto_rebuild: false)
        docs.each { |doc, cat| lsi.add_item(doc, cat) }

        times = {}
        times[:add_items] = 0

        times[:build_index] = Benchmark.measure { lsi.build_index }.total

        test_doc = 'This is about dogs. Dogs!'
        times[:classify] = Benchmark.measure { 100.times { lsi.classify(test_doc) } }.total
        times[:search] = Benchmark.measure { 100.times { lsi.search('dogs pets', 5) } }.total

        sample = docs.first[0]
        times[:find_related] = Benchmark.measure { 100.times { lsi.find_related(sample, 5) } }.total

        print Marshal.dump(times)
      RUBY
    ], err: [:child, :out])

    begin
      output = io.read
      native_results[size] = Marshal.load(output)
      puts "  #{size} docs: OK"
    rescue StandardError => e
      puts "  #{size} docs: FAILED (#{e.class.name.split('::').last})"
      native_results[size] = nil
    ensure
      io.close
    end
  end

  # Run GSL benchmarks in subprocess
  puts "\n>>> Running GSL benchmarks..."
  sizes.each do |size|
    docs = doc_sets[size]
    docs_literal = docs.map { |d, c| "[#{d.inspect}, #{c.inspect}]" }.join(', ')

    io = IO.popen([
      RbConfig.ruby,
      '-I', File.expand_path('../lib', __dir__),
      '-e', <<~RUBY
        ENV['SUPPRESS_GSL_WARNING'] = 'true'
        require 'benchmark'
        require 'classifier'

        unless Classifier::LSI.gsl_available
          print "GSL_NOT_AVAILABLE"
          exit 0
        end

        docs = [#{docs_literal}]
        lsi = Classifier::LSI.new(auto_rebuild: false)
        docs.each { |doc, cat| lsi.add_item(doc, cat) }

        times = {}
        times[:add_items] = 0

        times[:build_index] = Benchmark.measure { lsi.build_index }.total

        test_doc = 'This is about dogs. Dogs!'
        times[:classify] = Benchmark.measure { 100.times { lsi.classify(test_doc) } }.total
        times[:search] = Benchmark.measure { 100.times { lsi.search('dogs pets', 5) } }.total

        sample = docs.first[0]
        times[:find_related] = Benchmark.measure { 100.times { lsi.find_related(sample, 5) } }.total

        print Marshal.dump(times)
      RUBY
    ], err: [:child, :out])

    begin
      output = io.read
      if output == 'GSL_NOT_AVAILABLE'
        puts "  #{size} docs: SKIPPED (GSL not installed)"
        gsl_results[size] = nil
      else
        gsl_results[size] = Marshal.load(output)
        puts "  #{size} docs: OK"
      end
    rescue StandardError => e
      puts "  #{size} docs: FAILED (#{e.class.name.split('::').last})"
      gsl_results[size] = nil
    ensure
      io.close
    end
  end

  # Print comparison
  puts "\n#{'=' * 70}"
  puts 'COMPARISON SUMMARY (seconds, lower is better)'
  puts '=' * 70

  operations = %i[build_index classify search find_related]

  sizes.each do |size|
    native = native_results[size]
    gsl = gsl_results[size]

    next unless native || gsl

    puts "\n--- #{size} Documents ---"
    puts "%-20s %12s %12s %12s" % ['Operation', 'Native', 'GSL', 'Speedup']
    puts '-' * 58

    operations.each do |op|
      native_time = native ? native[op] : nil
      gsl_time = gsl ? gsl[op] : nil

      native_str = native_time ? format('%0.4f', native_time) : 'N/A'
      gsl_str = gsl_time ? format('%0.4f', gsl_time) : 'N/A'

      speedup = if native_time && gsl_time && gsl_time > 0
                  format('%0.1fx', native_time / gsl_time)
                else
                  'N/A'
                end

      puts "%-20s %12s %12s %12s" % [op, native_str, gsl_str, speedup]
    end

    if native && gsl
      native_total = operations.sum { |op| native[op] }
      gsl_total = operations.sum { |op| gsl[op] }
      speedup = gsl_total > 0 ? native_total / gsl_total : 0
      puts '-' * 58
      puts "%-20s %12.4f %12.4f %11.1fx" % ['TOTAL', native_total, gsl_total, speedup]
    end
  end

  puts "\n" + '=' * 70
  if gsl_results.values.all?(&:nil?)
    puts "Note: GSL gem not installed. Install with: gem install gsl"
    puts "      On macOS: brew install gsl && gem install gsl"
  end
  if native_results.values.any?(&:nil?)
    puts "Note: Some Native Ruby benchmarks failed due to SVD numerical limits."
  end
end

# Main
if $PROGRAM_NAME == __FILE__
  if ARGV.include?('--compare')
    run_comparison
  else
    run_single
  end
end
