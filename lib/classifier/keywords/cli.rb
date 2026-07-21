# rbs_inline: enabled

require 'optparse'
require 'fileutils'
require 'stringio'
require 'classifier'

module Classifier
  module Keywords
    class CLI
      class UsageError < StandardError; end

      # @rbs @args: Array[String]
      # @rbs @stdin: String?
      # @rbs @options: Hash[Symbol, untyped]
      # @rbs @output: Array[String]
      # @rbs @error: Array[String]
      # @rbs @exit_code: Integer
      # @rbs @parser: OptionParser

      def initialize(args, stdin: nil)
        @args = args.dup
        @stdin = stdin
        @options = {
          model: File.expand_path('./keywords.json'),
          top: nil,
          quiet: false,
          min_df: 1,
          max_df: 1.0,
          ngram_range: [1, 1]
        }
        @output = []
        @error = []
        @exit_code = 0
      end

      def run
        parse_options
        execute_command
        { output: @output.join("\n"), error: @error.join("\n"), exit_code: @exit_code }
      rescue OptionParser::InvalidOption, OptionParser::MissingArgument,
             OptionParser::InvalidArgument, UsageError => e
        @error << "Error: #{e.message}"
        @exit_code = 2
        { output: @output.join("\n"), error: @error.join("\n"), exit_code: @exit_code }
      rescue StandardError => e
        @error << "Error: #{e.message}"
        @exit_code = 1
        { output: @output.join("\n"), error: @error.join("\n"), exit_code: @exit_code }
      end

      private

      def parse_options
        @parser = OptionParser.new do |opts|
          opts.banner = 'Usage: keywords [text] [options] [command] [arguments]'
          opts.separator ''
          opts.separator 'Commands:'
          opts.separator '  fit <files...>     Fit the model from files or stdin (each line is treated as a separate document)'
          opts.separator '  extract <file>     Extract keywords from a file'
          opts.separator '  info               Show model information'
          opts.separator '  <text>             Get weighted terms from text'
          opts.separator ''
          opts.separator 'Options:'

          opts.on('-m', '--model FILE', 'Model file (default: ./keywords.json)') do |file|
            @options[:model] = File.expand_path(file)
          end

          opts.on('-n', '--top N', Integer, 'Show top N terms only') do |n|
            raise OptionParser::InvalidArgument, 'must be positive' unless n.positive?

            @options[:top] = n
          end

          opts.on('--min-df N', Integer, 'Minimum document frequency (default: 1)') do |n|
            @options[:min_df] = n
          end

          opts.on('--max-df N', Float, 'Maximum document frequency ratio (default: 1.0)') do |n|
            @options[:max_df] = n
          end

          opts.on('--ngram MIN,MAX', Array, 'N-gram range (default: 1,1)') do |range|
            raise OptionParser::InvalidArgument, 'requires exactly two values' if range.count != 2

            raise OptionParser::InvalidArgument, 'must be integers' unless range.all? { |n| n =~ /\A\d+\z/ }

            min, max = range.map(&:to_i)

            raise OptionParser::InvalidArgument, 'bounds must be >= 1 and min <= max' if min < 1 || max < 1 || min > max

            @options[:ngram_range] = [min, max]
          end

          opts.on('-q', 'Quiet mode') do
            @options[:quiet] = true
          end

          opts.on('-v', '--version', 'Show version') do
            @output << Classifier::VERSION
            @exit_code = 0
            throw :done
          end

          opts.on('-h', '--help', 'Show help') do
            @output << opts.to_s
            @exit_code = 0
            throw :done
          end
        end

        catch(:done) do
          @parser.parse!(@args)
        end
      end

      def execute_command
        return if @exit_code != 0 || @output.any?

        command = @args.first

        case command
        when 'fit'
          command_fit
        when 'extract'
          command_extract
        when 'info'
          command_info
        else
          command_keywords
        end
      end

      def command_fit
        # @type var streams: Array[IO | StringIO]
        streams = []

        @args.shift

        streams =
          if @args.empty?
            [@stdin ? StringIO.new(@stdin.to_s) : $stdin]
          else
            files = @args.map { |arg| Dir.glob(arg).map { |f| File.expand_path(f) } }.flatten.uniq
            files.map { |f| File.open(f) }
          end

        tfidf = TFIDF.new(
          min_df: @options[:min_df],
          max_df: @options[:max_df],
          ngram_range: @options[:ngram_range]
        )
        tfidf.fit_from_stream(Streaming::MultiIO.new(streams))

        raise UsageError, 'No documents found to save the model' if tfidf.num_documents.zero?

        tfidf.save_to_file(@options[:model])
        @output << "Saved to #{@options[:model].inspect}" unless @options[:quiet]
      ensure
        streams.each(&:close) unless @args.empty?
      end

      def command_extract
        @args.shift

        document =
          if @args.empty?
            @stdin ? @stdin.to_s : $stdin.read
          else
            file = File.expand_path(@args.first)
            File.exist?(file) ? File.read(file) : @args.first
          end

        transform(document)
      end

      def command_info
        @args.shift

        tfidf = TFIDF.load_from_file(@options[:model])
        documents = number_with_delimiter(tfidf.num_documents)
        vocabulary = number_with_delimiter(tfidf.vocabulary.count)
        min_df = tfidf.min_df
        max_df = tfidf.max_df
        @output << format(
          "Documents: %<documents>s\nVocabulary: %<vocabulary>s\n" \
          "Min DF: %<min_df>d\nMax DF: %<max_df>.1f",
          documents: documents, vocabulary: vocabulary, min_df: min_df, max_df: max_df
        )
      end

      def command_keywords
        if @args.empty? && @stdin.nil? && $stdin.tty?
          show_getting_started
          return
        end

        document =
          if @args.empty?
            @stdin ? @stdin.to_s : $stdin.read
          else
            @args.join(' ')
          end

        transform(document)
      end

      def show_getting_started
        @output << 'Keywords - Keyword extraction and term analysis using TF-IDF'
        @output << ''
        @output << 'Get started by building a vocabulary (fitting data):'
        @output << ''
        @output << '  # Fit from files'
        @output << '  keywords fit corpus/*.txt'
        @output << ''
        @output << '  # Fit from stdin'
        @output << '  cat documents.txt | keywords fit'
        @output << ''
        @output << '  # Keep in mind that each line is treated as a separate document.'
        @output << ''
        @output << 'Then extract weighted terms and analyze text:'
        @output << ''
        @output << '  # Extract from string'
        @output << "  keywords 'Ruby is a programming language'"
        @output << '  # ruby:0.52 programming:0.41 language:0.38'
        @output << ''
        @output << '  # Extract from file (convenience alias)'
        @output << '  keywords extract article.txt'
        @output << ''
        @output << '  # Pipeline with stdin and web data'
        @output << '  curl -s https://example.com/article | keywords extract'
        @output << ''
        @output << 'Check model statistics:'
        @output << ''
        @output << '  keywords info'
        @output << '  # Documents: 1,234'
        @output << '  # Vocabulary: 5,678'
        @output << '  # Min DF: 1'
        @output << '  # Max DF: 1.0'
        @output << ''
        @output << 'General Options:'
        @output << '  -m, --model FILE       Model file (default: ./keywords.json)'
        @output << '  -n, --top N            Show top N terms only (e.g. keywords -n 5 "text...")'
        @output << ''
        @output << 'Fit-specific Options:'
        @output << '  --min-df N             Minimum document frequency (default: 1)'
        @output << '  --max-df N             Maximum document frequency ratio (default: 1.0)'
        @output << '  --ngram MIN,MAX        N-gram range (default: 1,1)'
        @output << ''
        @output << 'Run "keywords --help" for full usage.'
      end

      def transform(document)
        unless File.exist?(@options[:model])
          raise UsageError, "No model found; run 'keywords fit' first or " \
                            "pass correct model using the '-m' option."
        end

        stem_map = document.stem_to_word_hash
        tfidf = TFIDF.load_from_file(@options[:model])
        vector = tfidf.transform(document).sort_by { |_, v| v }.reverse
        vector = vector.first(@options[:top]) if @options[:top]
        @output << vector.map { |k, v| "#{stem_map[k]}:#{v.round(2)}" }.join(' ')
      end

      def number_with_delimiter(number, delimiter: ',')
        number.to_s.reverse.scan(/\d{1,3}/).join(delimiter).reverse
      end
    end
  end
end
