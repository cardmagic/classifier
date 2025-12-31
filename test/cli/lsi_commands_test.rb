require_relative '../test_helper'
require 'classifier/cli'

class LSICommandsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @model_path = File.join(@tmpdir, 'classifier.json')
    create_trained_lsi_model
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  def run_cli(*args, stdin: nil)
    cli = Classifier::CLI.new(args, stdin: stdin)
    cli.run
  end

  def create_trained_lsi_model
    # Create article files for training
    @articles = {}

    @articles['ruby.txt'] = File.join(@tmpdir, 'ruby.txt')
    File.write(@articles['ruby.txt'], 'Ruby is an elegant programming language for web development')

    @articles['python.txt'] = File.join(@tmpdir, 'python.txt')
    File.write(@articles['python.txt'], 'Python is a programming language for data science')

    @articles['rails.txt'] = File.join(@tmpdir, 'rails.txt')
    File.write(@articles['rails.txt'], 'Rails is a web framework built with Ruby programming')

    @articles['football.txt'] = File.join(@tmpdir, 'football.txt')
    File.write(@articles['football.txt'], 'Football is a popular sport with teams and goals')

    # Train LSI model
    run_cli('-m', 'lsi', 'train', 'tech', '-f', @model_path, @articles['ruby.txt'], @articles['python.txt'], @articles['rails.txt'])
    run_cli('-m', 'lsi', 'train', 'sports', '-f', @model_path, @articles['football.txt'])
  end

  #
  # Search Command
  #
  def test_search_returns_ranked_documents
    result = run_cli('search', 'programming language', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    # Should return documents with scores
    assert_match(/\.txt:\d+\.\d+/, result[:output])
  end

  def test_search_from_stdin
    result = run_cli('search', '-f', @model_path, stdin: 'web development')

    assert_equal 0, result[:exit_code]
    assert_match(/\.txt:\d+\.\d+/, result[:output])
  end

  def test_search_with_count_limit
    result = run_cli('search', '-n', '2', 'programming', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    lines = result[:output].strip.split("\n")

    assert_operator lines.size, :<=, 2
  end

  def test_search_fails_on_bayes_model
    bayes_model = File.join(@tmpdir, 'bayes.json')
    run_cli('train', 'spam', '-f', bayes_model, stdin: 'buy now')

    result = run_cli('search', 'query', '-f', bayes_model)

    assert_equal 1, result[:exit_code]
    assert_match(/lsi|search.*requires/i, result[:error])
  end

  #
  # Related Command
  #
  def test_related_finds_similar_documents
    result = run_cli('related', @articles['ruby.txt'], '-f', @model_path)

    assert_equal 0, result[:exit_code]
    # Should find rails.txt as related (both about Ruby)
    assert_match(/\.txt:\d+\.\d+/, result[:output])
  end

  def test_related_with_count_limit
    result = run_cli('related', '-n', '1', @articles['ruby.txt'], '-f', @model_path)

    assert_equal 0, result[:exit_code]
    lines = result[:output].strip.split("\n")

    assert_equal 1, lines.size
  end

  def test_related_fails_on_bayes_model
    bayes_model = File.join(@tmpdir, 'bayes.json')
    run_cli('train', 'spam', '-f', bayes_model, stdin: 'buy now')

    result = run_cli('related', 'some_file.txt', '-f', bayes_model)

    assert_equal 1, result[:exit_code]
    assert_match(/lsi|related.*requires/i, result[:error])
  end

  def test_related_with_nonexistent_item
    result = run_cli('related', '/nonexistent/file.txt', '-f', @model_path)

    assert_equal 1, result[:exit_code]
    assert_match(/not found|unknown|item/i, result[:error])
  end

  #
  # LSI Classification
  #
  def test_lsi_classify_text
    result = run_cli('-m', 'lsi', 'Ruby web framework', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    assert_equal 'tech', result[:output].strip.downcase
  end

  def test_lsi_classify_with_probabilities
    result = run_cli('-m', 'lsi', '-p', 'Ruby web framework', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    assert_match(/tech:\d+\.\d+/, result[:output].downcase)
  end
end
