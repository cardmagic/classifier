require_relative '../test_helper'
require 'classifier/cli'
require 'webmock/minitest'

class RegistryCommandsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @model_path = File.join(@tmpdir, 'classifier.json')
    @cache_dir = File.join(@tmpdir, 'cache')

    # Override cache directory for tests
    @original_cache = Classifier::CLI::CACHE_DIR
    Classifier::CLI.send(:remove_const, :CACHE_DIR)
    Classifier::CLI.const_set(:CACHE_DIR, @cache_dir)

    # Mock models.json response
    @models_json = {
      'version' => '1.0.0',
      'models' => {
        'spam-filter' => {
          'description' => 'Email spam detection',
          'type' => 'bayes',
          'categories' => %w[spam ham],
          'file' => 'models/spam-filter.json',
          'size' => '245KB'
        },
        'sentiment' => {
          'description' => 'Sentiment analysis',
          'type' => 'bayes',
          'categories' => %w[positive negative neutral],
          'file' => 'models/sentiment.json',
          'size' => '1.2MB'
        }
      }
    }.to_json

    # Mock classifier model response
    @model_json = Classifier::Bayes.new('Spam', 'Ham').tap do |b|
      b.train('Spam', 'buy now free money cheap')
      b.train('Ham', 'hello friend meeting project')
    end.to_json
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)

    # Restore original cache directory
    Classifier::CLI.send(:remove_const, :CACHE_DIR)
    Classifier::CLI.const_set(:CACHE_DIR, @original_cache)

    WebMock.reset!
  end

  def run_cli(*args, stdin: nil)
    cli = Classifier::CLI.new(args, stdin: stdin)
    cli.run
  end

  #
  # Models Command
  #
  def test_models_lists_available_models
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: @models_json)

    result = run_cli('models')

    assert_equal 0, result[:exit_code]
    assert_match(/spam-filter/, result[:output])
    assert_match(/sentiment/, result[:output])
    assert_match(/bayes/, result[:output])
    assert_empty result[:error]
  end

  def test_models_from_custom_registry
    stub_request(:get, 'https://raw.githubusercontent.com/someone/models/main/models.json')
      .to_return(status: 200, body: @models_json)

    result = run_cli('models', '@someone/models')

    assert_equal 0, result[:exit_code]
    assert_match(/spam-filter/, result[:output])
    assert_empty result[:error]
  end

  def test_models_handles_empty_registry
    empty_json = { 'version' => '1.0.0', 'models' => {} }.to_json
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: empty_json)

    result = run_cli('models')

    assert_equal 0, result[:exit_code]
    assert_match(/no models found/i, result[:output])
  end

  def test_models_handles_network_error
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 404)
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/master/models.json')
      .to_return(status: 404)

    result = run_cli('models')

    assert_equal 1, result[:exit_code]
    assert_match(/failed to fetch/i, result[:error])
  end

  def test_models_local_lists_cached_models
    # Create some cached models
    models_dir = File.join(@cache_dir, 'models')
    FileUtils.mkdir_p(models_dir)
    File.write(File.join(models_dir, 'spam-filter.json'), @model_json)
    File.write(File.join(models_dir, 'sentiment.json'), @model_json)

    result = run_cli('models', '--local')

    assert_equal 0, result[:exit_code]
    assert_match(/spam-filter/, result[:output])
    assert_match(/sentiment/, result[:output])
    assert_match(/bayes/, result[:output])
    assert_empty result[:error]
  end

  def test_models_local_lists_models_from_custom_registries
    # Create cached model from custom registry
    custom_dir = File.join(@cache_dir, 'models', '@someone/models')
    FileUtils.mkdir_p(custom_dir)
    File.write(File.join(custom_dir, 'custom-model.json'), @model_json)

    result = run_cli('models', '--local')

    assert_equal 0, result[:exit_code]
    assert_match(/@someone\/models:custom-model/, result[:output])
  end

  def test_models_local_shows_no_models_when_cache_empty
    result = run_cli('models', '--local')

    assert_equal 0, result[:exit_code]
    assert_match(/no local models found/i, result[:output])
  end

  def test_models_local_shows_no_models_when_cache_dir_missing
    # Cache dir doesn't exist by default in test setup
    FileUtils.rm_rf(@cache_dir)

    result = run_cli('models', '--local')

    assert_equal 0, result[:exit_code]
    assert_match(/no local models found/i, result[:output])
  end

  #
  # Pull Command
  #
  def test_pull_downloads_model
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: @models_json)
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models/spam-filter.json')
      .to_return(status: 200, body: @model_json)

    result = run_cli('pull', 'spam-filter')

    assert_equal 0, result[:exit_code]
    assert_match(/downloading/i, result[:output])
    assert_match(/saved/i, result[:output])

    cached_path = File.join(@cache_dir, 'models', 'spam-filter.json')

    assert_path_exists cached_path
  end

  def test_pull_with_custom_output_path
    output_path = File.join(@tmpdir, 'my-model.json')

    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: @models_json)
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models/spam-filter.json')
      .to_return(status: 200, body: @model_json)

    result = run_cli('pull', 'spam-filter', '-o', output_path)

    assert_equal 0, result[:exit_code]
    assert_path_exists output_path
  end

  def test_pull_from_custom_registry
    stub_request(:get, 'https://raw.githubusercontent.com/someone/models/main/models.json')
      .to_return(status: 200, body: @models_json)
    stub_request(:get, 'https://raw.githubusercontent.com/someone/models/main/models/spam-filter.json')
      .to_return(status: 200, body: @model_json)

    result = run_cli('pull', '@someone/models:spam-filter')

    assert_equal 0, result[:exit_code]

    cached_path = File.join(@cache_dir, 'models', '@someone/models', 'spam-filter.json')

    assert_path_exists cached_path
  end

  def test_pull_model_not_found
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: @models_json)

    result = run_cli('pull', 'nonexistent')

    assert_equal 1, result[:exit_code]
    assert_match(/not found/i, result[:error])
  end

  def test_pull_requires_model_name
    result = run_cli('pull')

    assert_equal 2, result[:exit_code]
    assert_match(/model name required/i, result[:error])
  end

  def test_pull_quiet_mode
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: @models_json)
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models/spam-filter.json')
      .to_return(status: 200, body: @model_json)

    result = run_cli('pull', 'spam-filter', '-q')

    assert_equal 0, result[:exit_code]
    assert_empty result[:output]
  end

  #
  # Push Command
  #
  def test_push_shows_instructions
    result = run_cli('push', 'my-model.json')

    assert_equal 0, result[:exit_code]
    assert_match(/fork/i, result[:output])
    assert_match(/classifier-models/i, result[:output])
    assert_match(/pull request/i, result[:output])
  end

  #
  # Remote Classification (-r)
  #
  def test_classify_with_remote_model
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: @models_json)
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models/spam-filter.json')
      .to_return(status: 200, body: @model_json)

    result = run_cli('-r', 'spam-filter', 'buy now free money')

    assert_equal 0, result[:exit_code]
    # Last line should be the classification result
    assert_equal 'spam', result[:output].strip.split("\n").last.downcase
  end

  def test_classify_with_cached_remote_model
    # Pre-cache the model
    cached_path = File.join(@cache_dir, 'models', 'spam-filter.json')
    FileUtils.mkdir_p(File.dirname(cached_path))
    File.write(cached_path, @model_json)

    # Should not make any network requests since model is cached
    result = run_cli('-r', 'spam-filter', 'buy now free money')

    assert_equal 0, result[:exit_code]
    assert_equal 'spam', result[:output].strip.downcase
  end

  def test_classify_with_remote_from_custom_registry
    stub_request(:get, 'https://raw.githubusercontent.com/someone/models/main/models.json')
      .to_return(status: 200, body: @models_json)
    stub_request(:get, 'https://raw.githubusercontent.com/someone/models/main/models/spam-filter.json')
      .to_return(status: 200, body: @model_json)

    result = run_cli('-r', '@someone/models:spam-filter', 'buy now free money')

    assert_equal 0, result[:exit_code]
    # Last line should be the classification result
    assert_equal 'spam', result[:output].strip.split("\n").last.downcase
  end

  def test_classify_with_probabilities_and_remote
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models.json')
      .to_return(status: 200, body: @models_json)
    stub_request(:get, 'https://raw.githubusercontent.com/cardmagic/classifier-models/main/models/spam-filter.json')
      .to_return(status: 200, body: @model_json)

    result = run_cli('-r', 'spam-filter', '-p', 'buy now free money')

    assert_equal 0, result[:exit_code]
    assert_match(/spam:\d+\.\d+/, result[:output].downcase)
    assert_match(/ham:\d+\.\d+/, result[:output].downcase)
  end

  #
  # Helper Methods
  #
  def test_parse_model_spec_simple_name
    cli = Classifier::CLI.new([])
    registry, model = cli.send(:parse_model_spec, 'sentiment')

    assert_nil registry
    assert_equal 'sentiment', model
  end

  def test_parse_model_spec_custom_registry
    cli = Classifier::CLI.new([])
    registry, model = cli.send(:parse_model_spec, '@user/repo:sentiment')

    assert_equal 'user/repo', registry
    assert_equal 'sentiment', model
  end

  def test_parse_model_spec_registry_only
    cli = Classifier::CLI.new([])
    registry, model = cli.send(:parse_model_spec, '@user/repo')

    assert_equal 'user/repo', registry
    assert_nil model
  end

  def test_cache_path_for_default_registry
    cli = Classifier::CLI.new([])
    path = cli.send(:cache_path_for, 'cardmagic/classifier-models', 'sentiment')

    assert_match %r{models/sentiment\.json$}, path
    refute_match(/@/, path)
  end

  def test_cache_path_for_custom_registry
    cli = Classifier::CLI.new([])
    path = cli.send(:cache_path_for, 'user/repo', 'sentiment')

    assert_match %r{@user/repo/sentiment\.json$}, path
  end
end
