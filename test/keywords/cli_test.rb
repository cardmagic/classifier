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

    def test_fit_command_with_invalid_ngram
      result = run_cli(
        '-m', @model_path, '--min-df', '2', '--max-df', '0.5', '--ngram', '12',
        'fit',
        stdin: 'Cats are independent and self-sufficient'
      )

      assert_equal 2, result[:exit_code]
      assert_match('must have only 2 integers', result[:error])
      refute_path_exists @model_path
    end

    def test_extract_command
      make_model
      result = run_cli('-m', @model_path, '-n', '1', 'extract', 'Dogs and cats are great')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.680918560398684', result[:output])
      refute_match('cat:0.5178561161676974', result[:output])
      refute_match('dog:0.5178561161676974', result[:output])
    end

    def test_extract_command_stdin
      make_model
      result = run_cli('-m', @model_path, '-n', '1', 'extract', stdin: 'Dogs and cats are great')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.680918560398684', result[:output])
      refute_match('cat:0.5178561161676974', result[:output])
      refute_match('dog:0.5178561161676974', result[:output])
    end

    def test_keywords_command
      make_model
      result = run_cli('-m', @model_path, '-n', '1', 'Dogs and cats are great')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.680918560398684', result[:output])
      refute_match('cat:0.5178561161676974', result[:output])
      refute_match('dog:0.5178561161676974', result[:output])
    end

    def test_keywords_command_stdin
      make_model
      result = run_cli('-m', @model_path, '-n', '1', stdin: 'Dogs and cats are great')

      assert_equal 0, result[:exit_code]
      assert_match('great:0.680918560398684', result[:output])
      refute_match('cat:0.5178561161676974', result[:output])
      refute_match('dog:0.5178561161676974', result[:output])
    end

    def test_info_command
      make_model
      result = run_cli('-m', @model_path, 'info')

      assert_equal 0, result[:exit_code]
      assert_match("Documents: 3\nVocabulary: 9\nMin DF: 1\nMax DF: 1.0", result[:output])
    end
  end
end
