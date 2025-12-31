require_relative '../test_helper'
require 'classifier/cli'

class LRCommandsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @model_path = File.join(@tmpdir, 'classifier.json')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  def run_cli(*args, stdin: nil)
    cli = Classifier::CLI.new(args, stdin: stdin)
    cli.run
  end

  def create_trained_lr_model
    run_cli('-m', 'lr', 'train', 'spam', '-f', @model_path, stdin: "buy now\nfree money\nlimited offer\nclick here")
    run_cli('-m', 'lr', 'train', 'ham', '-f', @model_path, stdin: "hello friend\nmeeting tomorrow\nproject update\nweekly report")
  end

  def create_fitted_lr_model
    create_trained_lr_model
    run_cli('fit', '-f', @model_path)
  end

  #
  # Explicit Fit Required
  #
  def test_classify_without_fit_fails
    create_trained_lr_model

    # Should fail - model not fitted
    result = run_cli('-m', 'lr', 'buy now free money', '-f', @model_path)

    assert_equal 1, result[:exit_code]
    assert_match(/not fitted|run.*fit/i, result[:error])
  end

  def test_classify_after_fit_succeeds
    create_fitted_lr_model

    result = run_cli('-m', 'lr', 'buy now free money', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    assert_equal 'spam', result[:output].strip.downcase
  end

  def test_lr_info_shows_fit_status_before_fit
    create_trained_lr_model

    result = run_cli('info', '-f', @model_path)
    info = JSON.parse(result[:output])

    refute info['fitted']
  end

  def test_lr_info_shows_fit_status_after_fit
    create_fitted_lr_model

    result = run_cli('info', '-f', @model_path)
    info = JSON.parse(result[:output])

    assert info['fitted']
  end

  #
  # Fit Command
  #
  def test_fit_command
    create_trained_lr_model

    result = run_cli('fit', '-f', @model_path)

    assert_equal 0, result[:exit_code]

    result = run_cli('info', '-f', @model_path)
    info = JSON.parse(result[:output])

    assert info['fitted']
  end

  def test_fit_on_bayes_is_noop
    # Create a bayes model
    run_cli('train', 'spam', '-f', @model_path, stdin: 'buy now')

    result = run_cli('fit', '-f', @model_path)

    # Should succeed (no-op for Bayes)
    assert_equal 0, result[:exit_code]
  end

  def test_fit_after_additional_training_invalidates
    create_fitted_lr_model

    # Add more training data
    run_cli('-m', 'lr', 'train', 'spam', '-f', @model_path, stdin: 'win big prizes')

    # Info should show needs re-fitting
    result = run_cli('info', '-f', @model_path)
    info = JSON.parse(result[:output])

    refute info['fitted']
  end

  #
  # LR Hyperparameters
  #
  def test_lr_with_learning_rate
    result = run_cli('-m', 'lr', '--learning-rate', '0.001', 'train', 'spam', '-f', @model_path, stdin: 'buy now')

    assert_equal 0, result[:exit_code]
  end

  def test_lr_with_regularization
    result = run_cli('-m', 'lr', '--regularization', '0.1', 'train', 'spam', '-f', @model_path, stdin: 'buy now')

    assert_equal 0, result[:exit_code]
  end

  def test_lr_with_max_iterations
    result = run_cli('-m', 'lr', '--max-iterations', '500', 'train', 'spam', '-f', @model_path, stdin: 'buy now')

    assert_equal 0, result[:exit_code]
  end

  #
  # LR Classification with Probabilities
  #
  def test_lr_classify_with_probabilities
    create_fitted_lr_model

    result = run_cli('-m', 'lr', '-p', 'buy now free money', '-f', @model_path)

    assert_equal 0, result[:exit_code]
    # LR should give good probability estimates
    assert_match(/spam:\d+\.\d+/, result[:output].downcase)
    assert_match(/ham:\d+\.\d+/, result[:output].downcase)
  end
end
