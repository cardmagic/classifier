# frozen_string_literal: true

require_relative '../test_helper'
require 'classifier/keywords/cli'

module Keywords
  class CLITest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      @model_path = File.join(@tmpdir, 'keywords.json')
    end

    def teardown
      FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    end

    def run_cli(*args, stdin: nil)
      cli = Classifier::Keywords::CLI.new(args, stdin: stdin)
      cli.run
    end

    def make_articles
      Dir.mkdir(File.join(@tmpdir, 'articles'))
      File.write(File.join(@tmpdir, 'articles', 'a1.txt'), <<~TEXT)
        Dogs are loyal pets
        Dogs are great pets and very loyal
      TEXT
      File.write(File.join(@tmpdir, 'articles', 'a2.txt'), <<~TEXT)
        Cats are independent and self-sufficient
        Dogs are great
      TEXT
      File.write(File.join(@tmpdir, 'articles', 'a3.txt'), <<~TEXT)
        Birds can fly and sing beautiful songs
        Dogs and cats are popular pets
      TEXT
    end

    def make_model
      tfidf = Classifier::TFIDF.new
      tfidf.fit(
        [
          'Dogs are great pets and very loyal',
          'Cats are independent and self-sufficient',
          'Dogs and cats are popular pets'
        ]
      )
      tfidf.save_to_file(@model_path)
    end

    def make_bigram_model
      tfidf = Classifier::TFIDF.new(ngram_range: [1, 2])
      tfidf.fit(
        [
          'Machine learning creates smart systems',
          'Tech companies build machine learning tools',
          'Modern machine learning relies heavily on advanced neural networks',
          'Powerful machine learning drives advanced neural networks'
        ]
      )
      tfidf.save_to_file(@model_path)
    end

    def make_min_word_len2_model
      tfidf = Classifier::TFIDF.new(min_word_length: 2)
      tfidf.fit(
        [
          'go to db',
          'db is an elegant store',
          'go build web apps'
        ]
      )
      tfidf.save_to_file(@model_path)
    end

    def test_help_flag
      result = run_cli('-h')

      assert_match('Usage:', result[:output])
      assert_match('Commands:', result[:output])
      assert_match('Options:', result[:output])
      assert_equal 0, result[:exit_code]
    end

    def test_version_flag
      result = run_cli('-v')

      assert_match(/\d+\.\d+\.\d+/, result[:output])
      assert_equal 0, result[:exit_code]
    end

    def test_keywords_without_args
      unless $stdin.tty?
        skip(
          'This test should be skipped if the stdin contains data, ' \
          "i.e. the test is run like this: echo '' | bundle exec rake"
        )
      end
      result = run_cli

      assert_match('Keyword extraction and term analysis using TF-IDF', result[:output])
      assert_match('Run "keywords --help" for full usage.', result[:output])
      assert_equal 0, result[:exit_code]
    end

    def test_fit_command
      make_articles
      result = run_cli('-m', @model_path, 'fit', File.join(@tmpdir, 'articles/*.txt'))

      assert_equal 0, result[:exit_code]
      assert_predicate File.size(@model_path), :positive?
    end

    def test_fit_command_stdin
      result = run_cli(
        '-m', @model_path, '--min-df', '2', '--max-df', '0.5', '--ngram', '1,2',
        'fit',
        stdin: 'Cats are independent and self-sufficient'
      )

      assert_equal 0, result[:exit_code]
      assert_predicate File.size(@model_path), :positive?
    end

    def test_fit_command_with_invalid_ngram_one_value
      result = run_cli(
        '-m', @model_path, '--min-df', '2', '--max-df', '0.5', '--ngram', '12',
        'fit',
        stdin: 'Cats are independent and self-sufficient'
      )

      assert_equal 2, result[:exit_code]
      assert_match('requires exactly two values', result[:error])
      refute_path_exists @model_path
    end

    def test_fit_command_with_invalid_ngram_three_value
      result = run_cli(
        '-m', @model_path, '--min-df', '2', '--max-df', '0.5', '--ngram', '1,2,3',
        'fit',
        stdin: 'Cats are independent and self-sufficient'
      )

      assert_equal 2, result[:exit_code]
      assert_match('requires exactly two values', result[:error])
      refute_path_exists @model_path
    end

    def test_fit_command_with_invalid_ngram_value_not_integers
      result = run_cli(
        '-m', @model_path, '--min-df', '2', '--max-df', '0.5', '--ngram', '1abc,2xyz',
        'fit',
        stdin: 'Cats are independent and self-sufficient'
      )

      assert_equal 2, result[:exit_code]
      assert_match('must be integers', result[:error])
      refute_path_exists @model_path
    end

    def test_fit_command_with_zero_ngram_bounds_error
      result = run_cli(
        '-m', @model_path, '--min-df', '2', '--max-df', '0.5', '--ngram', '0,1',
        'fit',
        stdin: 'Cats are independent and self-sufficient'
      )

      assert_equal 2, result[:exit_code]
      assert_match('bounds must be >= 1 and min <= max', result[:error])
      refute_path_exists @model_path
    end

    def test_fit_command_with_ngram_min_exceeds_max_error
      result = run_cli(
        '-m', @model_path, '--min-df', '2', '--max-df', '0.5', '--ngram', '2,1',
        'fit',
        stdin: 'Cats are independent and self-sufficient'
      )

      assert_equal 2, result[:exit_code]
      assert_match('bounds must be >= 1 and min <= max', result[:error])
      refute_path_exists @model_path
    end

    def test_fit_command_with_no_documents
      result = run_cli('-m', @model_path, 'fit', stdin: '')

      assert_equal 2, result[:exit_code]
      assert_match('No documents found to save the model', result[:error])
      refute_path_exists @model_path
    end

    def test_extract_command_with_not_exists_input_file
      make_model
      file = File.join(@tmpdir, 'not_exists.txt')

      result = run_cli('-m', @model_path, '-n', '1', 'extract', file)

      assert_equal 2, result[:exit_code]
      assert_match("Error: File \"#{file}\" does not exists", result[:error])
    end

    def test_extract_command
      make_model
      file = File.join(@tmpdir, 'a.txt')
      File.write(file, 'Dogs and cats are great')

      result = run_cli('-m', @model_path, '-n', '1', 'extract', file)

      assert_equal 0, result[:exit_code]
      assert_match('great:0.68', result[:output])
      refute_match('cats:0.52', result[:output])
      refute_match('dogs:0.52', result[:output])
    end

    def test_extract_command_stdin
      make_model
      result = run_cli('-m', @model_path, '-n', '1', 'extract', stdin: 'Dogs and cats are great')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.68', result[:output])
      refute_match('cats:0.52', result[:output])
      refute_match('dogs:0.52', result[:output])
    end

    def test_keywords_command
      make_model
      result = run_cli('-m', @model_path, '-n', '1', 'Dogs and cats are great')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.68', result[:output])
      refute_match('cats:0.52', result[:output])
      refute_match('dogs:0.52', result[:output])
    end

    def test_keywords_command_stdin
      make_model
      result = run_cli('-m', @model_path, '-n', '1', stdin: 'Dogs and cats are great')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.68', result[:output])
      refute_match('cats:0.52', result[:output])
      refute_match('dogs:0.52', result[:output])
    end

    def test_keywords_command_output_original_words
      make_model
      result = run_cli('-m', @model_path, 'Dogs and cats are great. Large dog. Smart dog')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.38', result[:output])
      assert_match('cats:0.29', result[:output])
      assert_match('dog:0.88', result[:output])
    end

    def test_keywords_command_with_not_existing_model
      result = run_cli('-m', @model_path, 'Dogs and cats are great')

      assert_equal 2, result[:exit_code]
      assert_match('No model found', result[:error])
    end

    def test_keywords_command_with_negative_top_option
      make_model
      result = run_cli('-m', @model_path, '-n', '-2', 'Dogs and cats are great')

      assert_equal 2, result[:exit_code]
      assert_match('must be positive', result[:error])
    end

    def test_keywords_command_with_bigram_model
      make_bigram_model
      result = run_cli('-m', @model_path, 'machine learning neural networks')

      assert_equal 0, result[:exit_code]
      assert_match('neural networks:0.48', result[:output])
      assert_match('networks:0.48', result[:output])
      assert_match('neural:0.48', result[:output])
      assert_match('machine learning:0.32', result[:output])
      assert_match('learning:0.32', result[:output])
      assert_match('machine:0.32', result[:output])
    end

    def test_keywords_command_with_min_word_len2_model
      make_min_word_len2_model
      result = run_cli('-m', @model_path, 'go to db elegant store')

      assert_equal 0, result[:exit_code]
      assert_match('store:0.56', result[:output])
      assert_match('elegant:0.56', result[:output])
      assert_match('db:0.43', result[:output])
      assert_match('go:0.43', result[:output])
    end

    def test_info_command
      make_model
      result = run_cli('-m', @model_path, 'info')

      assert_equal 0, result[:exit_code]
      assert_match("Documents: 3\nVocabulary: 9\nMin DF: 1\nMax DF: 1.0", result[:output])
    end

    def test_info_command_with_not_existing_model
      result = run_cli('-m', @model_path, 'info')

      assert_equal 2, result[:exit_code]
      assert_match('No model found', result[:error])
    end
  end
end
