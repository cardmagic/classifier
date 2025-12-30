require_relative '../test_helper'
require 'classifier/cli'

class CLITest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @model_path = File.join(@tmpdir, 'classifier.json')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  # Helper to run CLI and capture output
  def run_cli(*args, stdin: nil)
    cli = Classifier::CLI.new(args, stdin: stdin)
    cli.run
  end

  # Helper to create a trained model for testing
  def create_trained_bayes_model
    run_cli('train', 'spam', '-f', @model_path, stdin: "buy now\nfree money\nlimited offer")
    run_cli('train', 'ham', '-f', @model_path, stdin: "hello friend\nmeeting tomorrow\nproject update")
  end

  #
  # Version and Help
  #
  def test_version_flag
    result = run_cli('-v')

    assert_match(/\d+\.\d+\.\d+/, result[:output])
    assert_equal 0, result[:exit_code]
  end

  def test_help_flag
    result = run_cli('-h')

    assert_match(/usage:/i, result[:output])
    assert_match(/train/, result[:output])
    assert_match(/classify/i, result[:output])
    assert_equal 0, result[:exit_code]
  end

  def test_getting_started_when_no_model_and_no_args
    result = run_cli('-f', @model_path)

    assert_match(/Get started by training/, result[:output])
    assert_match(/classifier train spam/, result[:output])
    assert_match(/classifier --help/, result[:output])
    assert_equal 0, result[:exit_code]
    assert_empty result[:error]
  end

  #
  # Train Command
  #
  def test_train_from_stdin
    result = run_cli('train', 'spam', '-f', @model_path, stdin: "buy now\nfree money")

    assert_equal 0, result[:exit_code]
    assert_path_exists @model_path
  end

  def test_train_from_file
    corpus_file = File.join(@tmpdir, 'spam.txt')
    File.write(corpus_file, "buy now\nfree money\nlimited offer")

    result = run_cli('train', 'spam', '-f', @model_path, corpus_file)

    assert_equal 0, result[:exit_code]
    assert_path_exists @model_path
  end

  def test_train_multiple_files
    file1 = File.join(@tmpdir, 'spam1.txt')
    file2 = File.join(@tmpdir, 'spam2.txt')
    File.write(file1, 'buy now')
    File.write(file2, 'free money')

    result = run_cli('train', 'spam', '-f', @model_path, file1, file2)

    assert_equal 0, result[:exit_code]
  end

  def test_train_requires_category
    result = run_cli('train', '-f', @model_path)

    assert_equal 2, result[:exit_code]
    assert_match(/category/i, result[:error])
  end

  def test_train_multiple_categories
    run_cli('train', 'spam', '-f', @model_path, stdin: 'buy now')
    result = run_cli('train', 'ham', '-f', @model_path, stdin: 'hello friend')

    assert_equal 0, result[:exit_code]

    # Verify both categories exist
    info = run_cli('info', '-f', @model_path)

    assert_match(/spam/i, info[:output])
    assert_match(/ham/i, info[:output])
  end

  #
  # Classify Command (Default Action)
  #
  def test_classify_text_argument
    create_trained_bayes_model

    result = run_cli('buy now free money', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    assert_equal 'spam', result[:output].strip.downcase
  end

  def test_classify_from_stdin
    create_trained_bayes_model

    result = run_cli('-f', @model_path, stdin: 'buy now free money')

    assert_equal 0, result[:exit_code]
    assert_equal 'spam', result[:output].strip.downcase
  end

  def test_classify_multiple_lines_from_stdin
    create_trained_bayes_model

    result = run_cli('-f', @model_path, stdin: "buy now\nmeeting tomorrow")
    lines = result[:output].strip.split("\n").map(&:downcase)

    assert_equal 2, lines.size
    assert_equal 'spam', lines[0]
    assert_equal 'ham', lines[1]
  end

  def test_classify_with_probabilities
    create_trained_bayes_model

    result = run_cli('-p', 'buy now free money', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    assert_match(/spam:\d+\.\d+/, result[:output].downcase)
    assert_match(/ham:\d+\.\d+/, result[:output].downcase)
  end

  def test_classify_without_model_fails
    result = run_cli('some text', '-f', '/nonexistent/model.json')

    assert_equal 1, result[:exit_code]
    assert_match(/model|not found|exist/i, result[:error])
  end

  #
  # Info Command
  #
  def test_info_shows_model_details
    create_trained_bayes_model

    result = run_cli('info', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    assert_match(/type:\s*bayes/i, result[:output])
    assert_match(/categories:/i, result[:output])
    assert_match(/spam/i, result[:output])
    assert_match(/ham/i, result[:output])
  end

  def test_info_without_model_fails
    result = run_cli('info', '-f', '/nonexistent/model.json')

    assert_equal 1, result[:exit_code]
  end

  #
  # Classifier Types
  #
  def test_train_with_lsi_type
    result = run_cli('-m', 'lsi', 'train', 'tech', '-f', @model_path, stdin: 'ruby programming language')

    assert_equal 0, result[:exit_code]

    info = run_cli('info', '-f', @model_path)

    assert_match(/type:\s*lsi/i, info[:output])
  end

  def test_train_with_knn_type
    result = run_cli('-m', 'knn', 'train', 'tech', '-f', @model_path, stdin: 'ruby programming language')

    assert_equal 0, result[:exit_code]

    info = run_cli('info', '-f', @model_path)

    assert_match(/type:\s*knn/i, info[:output])
  end

  def test_train_with_lr_type
    result = run_cli('-m', 'lr', 'train', 'tech', '-f', @model_path, stdin: 'ruby programming language')

    assert_equal 0, result[:exit_code]

    info = run_cli('info', '-f', @model_path)

    assert_match(/type:\s*logistic.?regression/i, info[:output])
  end

  def test_invalid_classifier_type
    result = run_cli('-m', 'invalid', 'train', 'spam', '-f', @model_path, stdin: 'test')

    assert_equal 2, result[:exit_code]
    assert_match(/invalid|unknown|type/i, result[:error])
  end

  #
  # KNN Options
  #
  def test_knn_with_k_option
    run_cli('-m', 'knn', '-k', '3', 'train', 'tech', '-f', @model_path, stdin: 'ruby programming')
    run_cli('-m', 'knn', 'train', 'sports', '-f', @model_path, stdin: 'football soccer')

    result = run_cli('-m', 'knn', '-k', '3', 'ruby code', '-f', @model_path)

    assert_equal 0, result[:exit_code]
  end

  #
  # Environment Variables
  #
  def test_model_from_environment_variable
    create_trained_bayes_model

    ENV['CLASSIFIER_MODEL'] = @model_path
    result = run_cli('buy now free money')

    assert_equal 0, result[:exit_code]
    assert_equal 'spam', result[:output].strip.downcase
  ensure
    ENV.delete('CLASSIFIER_MODEL')
  end

  def test_type_from_environment_variable
    ENV['CLASSIFIER_TYPE'] = 'lsi'
    ENV['CLASSIFIER_MODEL'] = @model_path

    result = run_cli('train', 'tech', stdin: 'programming code')

    assert_equal 0, result[:exit_code]

    info = run_cli('info')

    assert_match(/type:\s*lsi/i, info[:output])
  ensure
    ENV.delete('CLASSIFIER_TYPE')
    ENV.delete('CLASSIFIER_MODEL')
  end

  #
  # Quiet Mode
  #
  def test_quiet_mode_minimal_output
    create_trained_bayes_model

    result = run_cli('-q', 'buy now', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    # Quiet mode should just output the category, nothing else
    assert_equal 'spam', result[:output].strip.downcase
  end
end
