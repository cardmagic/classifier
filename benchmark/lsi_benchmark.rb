#!/usr/bin/env ruby
# frozen_string_literal: true

# LSI Benchmark Script
# Compares performance between native C extension and pure Ruby
#
# Usage:
#   rake benchmark               # Run with current configuration
#   rake benchmark:compare       # Run both native C and pure Ruby, show comparison
#   NATIVE_VECTOR=true rake benchmark  # Force pure Ruby mode
#
# The native C extension provides 5-10x speedup over pure Ruby.

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'benchmark'
require 'json'

# Sample documents with diverse vocabulary to avoid SVD dimension issues
CATEGORIES = {
  dog: [
    'Dogs are loyal companions who love to play fetch in the park.',
    'My golden retriever enjoys swimming and chasing squirrels.',
    'Puppies need training and patience to become well-behaved dogs.',
    'The veterinarian recommended a new diet for my aging dog.'
  ],
  cat: [
    'Cats are independent creatures who enjoy napping in sunny spots.',
    'My tabby cat loves to chase laser pointers around the room.',
    'Kittens are playful and curious about everything they see.',
    'The feline groomed herself after eating her favorite treats.'
  ],
  bird: [
    'Parrots can learn to mimic human speech with practice.',
    'The cardinal built a nest in our backyard oak tree.',
    'Hummingbirds visit our feeder every morning for nectar.',
    'Owls are nocturnal hunters with excellent night vision.'
  ],
  fish: [
    'Tropical aquariums require careful temperature and pH monitoring.',
    'Salmon swim upstream to spawn in their birthplace rivers.',
    'The coral reef teems with colorful marine life and fish.',
    'Goldfish are popular pets that can live for many years.'
  ],
  horse: [
    'Thoroughbreds are bred for speed and excel at racing.',
    'The rancher trained wild mustangs using gentle methods.',
    'Equestrian sports include dressage, jumping, and polo.',
    'Horses communicate through body language and vocalizations.'
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

  backend_name = Classifier::LSI.backend == :native ? 'Native C Extension' : 'Pure Ruby'
  docs = generate_documents(doc_count)

  puts "\n#{'=' * 60}"
  puts "LSI Benchmark: #{doc_count} documents (#{backend_name})"
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
    test_doc = 'My puppy loves playing fetch and going for walks.'
    results[:classify] = Benchmark.measure do
      100.times { lsi.classify(test_doc) }
    end

    # Benchmark: Search (100 iterations)
    results[:search] = Benchmark.measure do
      100.times { lsi.search('loyal companion pet', 5) }
    end

    # Benchmark: Find related (100 iterations)
    sample_doc = docs.first[0]
    results[:find_related] = Benchmark.measure do
      100.times { lsi.find_related(sample_doc, 5) }
    end

    # Print results
    puts format("\n%-20s %10s %10s %10s", 'Operation', 'User', 'System', 'Total')
    puts '-' * 52
    results.each do |name, bm|
      puts format("%-20s %10.4f %10.4f %10.4f", name, bm.utime, bm.stime, bm.total)
    end

    total = results.values.sum(&:total)
    puts '-' * 52
    puts format("%-20s %10s %10s %10.4f", 'TOTAL', '', '', total)

    { results: results, backend: Classifier::LSI.backend, success: true }
  rescue Math::DomainError, ExceptionForMatrix::ErrDimensionMismatch => e
    puts "\nFAILED: SVD numerical instability"
    puts "Error: #{e.class.name} - #{e.message}"
    { results: {}, backend: :ruby, success: false, error: e.message }
  end
end

def run_single
  sizes = [5, 10, 15, 20]
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
    puts 'Note: SVD may have numerical stability limits with very large datasets.'
  end
end

def run_subprocess(docs_json, env_vars = {})
  lib_path = File.expand_path('../lib', __dir__)

  # Build environment hash
  env = env_vars.transform_keys(&:to_s)

  popen_block = lambda do
    IO.popen([env, RbConfig.ruby, '-I', lib_path, '-W0', '-e', <<~'RUBY'], 'r+')
      require 'benchmark'
      require 'json'
      require 'classifier'

      docs = JSON.parse($stdin.read)
      lsi = Classifier::LSI.new(auto_rebuild: false)
      docs.each { |doc, cat| lsi.add_item(doc, cat.to_sym) }

      times = {}
      times[:add_items] = 0
      times[:backend] = Classifier::LSI.backend.to_s

      times[:build_index] = Benchmark.measure { lsi.build_index }.total

      test_doc = 'My puppy loves playing fetch and going for walks.'
      times[:classify] = Benchmark.measure { 100.times { lsi.classify(test_doc) } }.total
      times[:search] = Benchmark.measure { 100.times { lsi.search('loyal companion pet', 5) } }.total

      sample = docs.first[0]
      times[:find_related] = Benchmark.measure { 100.times { lsi.find_related(sample, 5) } }.total

      print Marshal.dump(times)
    RUBY
  end

  io = if defined?(Bundler)
         Bundler.with_unbundled_env(&popen_block)
       else
         popen_block.call
       end

  begin
    io.write(docs_json)
    io.close_write
    output = io.read
    { available: true, times: Marshal.load(output) }
  rescue StandardError => e
    { available: false, error: e }
  ensure
    io.close
  end
end

def run_comparison
  sizes = [5, 10, 15, 20]

  puts "#{'#' * 70}"
  puts '# LSI BENCHMARK: Native C Extension vs Pure Ruby Comparison'
  puts "#{'#' * 70}"

  ruby_results = {}
  native_results = {}

  # Generate documents once for consistency
  doc_sets = sizes.map { |s| [s, generate_documents(s)] }.to_h

  # Run pure Ruby benchmarks in subprocess
  puts "\n>>> Running Pure Ruby benchmarks..."
  sizes.each do |size|
    docs_json = JSON.generate(doc_sets[size])
    result = run_subprocess(docs_json, NATIVE_VECTOR: 'true', SUPPRESS_LSI_WARNING: 'true')

    if result[:error]
      puts "  #{size} docs: FAILED (#{result[:error].class.name.split('::').last})"
      ruby_results[size] = nil
    else
      ruby_results[size] = result[:times]
      puts "  #{size} docs: OK (backend: #{result[:times][:backend]})"
    end
  end

  # Run native C extension benchmarks in subprocess
  puts "\n>>> Running Native C Extension benchmarks..."
  sizes.each do |size|
    docs_json = JSON.generate(doc_sets[size])
    result = run_subprocess(docs_json, SUPPRESS_LSI_WARNING: 'true')

    if result[:error]
      puts "  #{size} docs: FAILED (#{result[:error].class.name.split('::').last})"
      native_results[size] = nil
    else
      native_results[size] = result[:times]
      puts "  #{size} docs: OK (backend: #{result[:times][:backend]})"
    end
  end

  # Print comparison
  puts "\n#{'=' * 70}"
  puts 'COMPARISON SUMMARY (seconds, lower is better)'
  puts '=' * 70

  operations = %i[build_index classify search find_related]

  sizes.each do |size|
    ruby = ruby_results[size]
    native = native_results[size]

    next unless ruby || native

    puts "\n--- #{size} Documents ---"
    puts format("%-20s %12s %12s %12s", 'Operation', 'Pure Ruby', 'Native C', 'Speedup')
    puts '-' * 58

    operations.each do |op|
      ruby_time = ruby ? ruby[op] : nil
      native_time = native ? native[op] : nil

      ruby_str = ruby_time ? format('%0.4f', ruby_time) : 'N/A'
      native_str = native_time ? format('%0.4f', native_time) : 'N/A'

      speedup = if ruby_time && native_time && native_time > 0
                  format('%0.1fx', ruby_time / native_time)
                else
                  'N/A'
                end

      puts format("%-20s %12s %12s %12s", op, ruby_str, native_str, speedup)
    end

    if ruby && native
      ruby_total = operations.sum { |op| ruby[op] }
      native_total = operations.sum { |op| native[op] }
      speedup = native_total > 0 ? ruby_total / native_total : 0
      puts '-' * 58
      puts format("%-20s %12.4f %12.4f %11.1fx", 'TOTAL', ruby_total, native_total, speedup)
    end
  end

  puts "\n" + '=' * 70
  if native_results.values.all? { |v| v.nil? || v[:backend] == 'ruby' }
    puts 'Note: Native C extension not available. Using pure Ruby fallback.'
    puts '      Compile with: rake compile'
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
