# rbs_inline: enabled

require 'json'
require 'optparse'
require 'classifier'

module Classifier
  class CLI
    # @rbs @args: Array[String]
    # @rbs @stdin: String?
    # @rbs @options: Hash[Symbol, untyped]
    # @rbs @output: Array[String]
    # @rbs @error: Array[String]
    # @rbs @exit_code: Integer
    # @rbs @parser: OptionParser

    CLASSIFIER_TYPES = {
      'bayes' => :bayes,
      'lsi' => :lsi,
      'knn' => :knn,
      'lr' => :logistic_regression,
      'logistic_regression' => :logistic_regression
    }.freeze

    def initialize(args, stdin: nil)
      @args = args.dup
      @stdin = stdin
      @options = {
        model: ENV.fetch('CLASSIFIER_MODEL', './classifier.json'),
        type: ENV.fetch('CLASSIFIER_TYPE', 'bayes'),
        probabilities: false,
        quiet: false,
        count: 10,
        k: 5,
        weighted: false,
        learning_rate: nil,
        regularization: nil,
        max_iterations: nil
      }
      @output = [] #: Array[String]
      @error = [] #: Array[String]
      @exit_code = 0
    end

    def run
      parse_options
      execute_command
      { output: @output.join("\n"), error: @error.join("\n"), exit_code: @exit_code }
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument, OptionParser::InvalidArgument => e
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
        opts.banner = 'Usage: classifier [options] [command] [arguments]'
        opts.separator ''
        opts.separator 'Commands:'
        opts.separator '  train <category> [files...]  Train a category from files or stdin'
        opts.separator '  info                         Show model information'
        opts.separator '  fit                          Fit the model (logistic regression)'
        opts.separator '  search <query>               Semantic search (LSI only)'
        opts.separator '  related <item>               Find related documents (LSI only)'
        opts.separator '  <text>                       Classify text (default action)'
        opts.separator ''
        opts.separator 'Options:'

        opts.on('-f', '--file FILE', 'Model file (default: ./classifier.json)') do |file|
          @options[:model] = file
        end

        opts.on('-m', '--model TYPE', 'Classifier model: bayes, lsi, knn, lr (default: bayes)') do |type|
          unless CLASSIFIER_TYPES.key?(type)
            raise OptionParser::InvalidArgument, "Unknown classifier model: #{type}. Valid models: #{CLASSIFIER_TYPES.keys.join(', ')}"
          end

          @options[:type] = type
        end

        opts.on('-p', 'Show probabilities') do
          @options[:probabilities] = true
        end

        opts.on('-n', '--count N', Integer, 'Number of results for search/related (default: 10)') do |n|
          @options[:count] = n
        end

        opts.on('-k', '--neighbors N', Integer, 'Number of neighbors for KNN (default: 5)') do |n|
          @options[:k] = n
        end

        opts.on('--weighted', 'Use distance-weighted voting for KNN') do
          @options[:weighted] = true
        end

        opts.on('--learning-rate N', Float, 'Learning rate for logistic regression (default: 0.1)') do |n|
          @options[:learning_rate] = n
        end

        opts.on('--regularization N', Float, 'L2 regularization for logistic regression (default: 0.01)') do |n|
          @options[:regularization] = n
        end

        opts.on('--max-iterations N', Integer, 'Max iterations for logistic regression (default: 100)') do |n|
          @options[:max_iterations] = n
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
      when 'train'
        command_train
      when 'info'
        command_info
      when 'fit'
        command_fit
      when 'search'
        command_search
      when 'related'
        command_related
      else
        command_classify
      end
    end

    def command_train
      @args.shift # remove 'train'
      category = @args.shift

      unless category
        @error << 'Error: category required for train command'
        @exit_code = 2
        return
      end

      classifier = load_or_create_classifier

      if classifier.is_a?(LSI) && @args.any?
        train_lsi_from_files(classifier, category, @args)
        save_classifier(classifier)
        return
      end

      text = read_training_input
      if text.empty?
        @error << 'Error: no training data provided'
        @exit_code = 2
        return
      end

      train_classifier(classifier, category, text)
      save_classifier(classifier)
    end

    def command_info
      unless File.exist?(@options[:model])
        @error << "Error: model not found at #{@options[:model]}"
        @exit_code = 1
        return
      end

      classifier = load_classifier
      info = build_model_info(classifier)
      @output << JSON.pretty_generate(info)
    end

    def build_model_info(classifier)
      info = { file: @options[:model], type: classifier_type_name(classifier) }
      add_common_info(info, classifier)
      add_classifier_specific_info(info, classifier)
      info
    end

    def add_common_info(info, classifier)
      info[:categories] = classifier.categories.map(&:to_s) if classifier.respond_to?(:categories)
      info[:training_count] = classifier.training_count if classifier.respond_to?(:training_count)
      info[:vocab_size] = classifier.vocab_size if classifier.respond_to?(:vocab_size)
      info[:fitted] = classifier.fitted? if classifier.respond_to?(:fitted?)
    end

    def add_classifier_specific_info(info, classifier)
      case classifier
      when Bayes then add_bayes_info(info, classifier)
      when LSI then add_lsi_info(info, classifier)
      when KNN then add_knn_info(info, classifier)
      end
    end

    def add_bayes_info(info, classifier)
      categories_data = classifier.instance_variable_get(:@categories)
      info[:category_stats] = classifier.categories.to_h do |cat|
        cat_data = categories_data[cat.to_sym] || {}
        [cat.to_s, { unique_words: cat_data.size, total_words: cat_data.values.sum }]
      end
    end

    def add_lsi_info(info, classifier)
      info[:documents] = classifier.items.size
      info[:items] = classifier.items
      categories = classifier.items.map { |item| classifier.categories_for(item) }.flatten.uniq
      info[:categories] = categories.map(&:to_s) unless categories.empty?
    end

    def add_knn_info(info, classifier)
      data = classifier.instance_variable_get(:@data) || []
      info[:documents] = data.size
      categories = data.map { |d| d[:category] }.uniq
      info[:categories] = categories.map(&:to_s) unless categories.empty?
    end

    def command_fit
      unless File.exist?(@options[:model])
        @error << "Error: model not found at #{@options[:model]}"
        @exit_code = 1
        return
      end

      classifier = load_classifier

      unless classifier.respond_to?(:fit)
        @output << 'Model does not require fitting' unless @options[:quiet]
        return
      end

      classifier.fit
      save_classifier(classifier)
      @output << 'Model fitted successfully' unless @options[:quiet]
    end

    def command_search
      @args.shift # remove 'search'

      unless File.exist?(@options[:model])
        @error << "Error: model not found at #{@options[:model]}"
        @exit_code = 1
        return
      end

      classifier = load_classifier

      unless classifier.is_a?(LSI)
        @error << 'Error: search requires LSI model (use -t lsi)'
        @exit_code = 1
        return
      end

      query = @args.join(' ')
      query = read_stdin_line if query.empty?

      if query.empty?
        @error << 'Error: search query required'
        @exit_code = 2
        return
      end

      results = classifier.search(query, @options[:count])
      results.each do |item|
        score = classifier.proximity_norms_for_content(query).find { |i, _| i == item }&.last || 0
        @output << "#{item}:#{format('%.2f', score)}"
      end
    end

    def command_related
      @args.shift # remove 'related'
      item = @args.shift

      unless item
        @error << 'Error: item required for related command'
        @exit_code = 2
        return
      end

      unless File.exist?(@options[:model])
        @error << "Error: model not found at #{@options[:model]}"
        @exit_code = 1
        return
      end

      classifier = load_classifier

      unless classifier.is_a?(LSI)
        @error << 'Error: related requires LSI model (use -t lsi)'
        @exit_code = 1
        return
      end

      unless classifier.items.include?(item)
        @error << "Error: item not found in model: #{item}"
        @exit_code = 1
        return
      end

      results = classifier.find_related(item, @options[:count])
      results.each do |related_item|
        scores = classifier.proximity_array_for_content(item)
        score = scores.find { |i, _| i == related_item }&.last || 0
        @output << "#{related_item}:#{format('%.2f', score)}"
      end
    end

    def command_classify
      text = @args.join(' ')

      if text.empty? && ($stdin.tty? || @stdin.nil?) && !File.exist?(@options[:model])
        show_getting_started
        return
      end

      unless File.exist?(@options[:model])
        @error << "Error: model not found at #{@options[:model]}"
        @exit_code = 1
        return
      end

      classifier = load_classifier

      if text.empty?
        lines = read_stdin_lines
        return show_model_usage(classifier) if lines.empty?

        lines.each { |line| classify_and_output(classifier, line) }
      else
        classify_and_output(classifier, text)
      end
    end

    # @rbs (untyped) -> void
    def show_model_usage(classifier)
      type = classifier_type_name(classifier)
      cats = classifier.categories.map(&:to_s).map(&:downcase)
      first_cat = cats.first || 'category'

      @output << "Model: #{@options[:model]} (#{type})"
      @output << "Categories: #{cats.join(', ')}"
      @output << ''
      @output << 'Classify text:'
      @output << ''
      @output << "  classifier 'text to classify'"
      @output << "  echo 'text to classify' | classifier"
      @output << ''
      @output << 'Train more data:'
      @output << ''
      @output << "  echo 'new example text' | classifier train #{first_cat}"
      @output << "  classifier train #{first_cat} file1.txt file2.txt"
      @output << ''
      @output << 'Other commands:'
      @output << ''
      @output << '  classifier info    Show model details (JSON)'
    end

    def classify_and_output(classifier, text)
      return if text.strip.empty?

      if classifier.is_a?(LogisticRegression) && !classifier.fitted?
        raise StandardError, "Model not fitted. Run 'classifier fit' after training."
      end

      if @options[:probabilities]
        probs = get_probabilities(classifier, text)
        formatted = probs.map { |cat, prob| "#{cat.downcase}:#{format('%.2f', prob)}" }.join(' ')
        @output << formatted
      else
        result = classifier.classify(text)
        @output << result.downcase
      end
    end

    def get_probabilities(classifier, text)
      if classifier.respond_to?(:probabilities)
        classifier.probabilities(text)
      elsif classifier.respond_to?(:classifications)
        scores = classifier.classifications(text)
        normalize_scores(scores)
      else
        { classifier.classify(text) => 1.0 }
      end
    end

    def normalize_scores(scores)
      max_score = scores.values.max
      exp_scores = scores.transform_values { |s| Math.exp(s - max_score) }
      total = exp_scores.values.sum.to_f
      exp_scores.transform_values { |s| (s / total).to_f }
    end

    def load_or_create_classifier
      if File.exist?(@options[:model])
        load_classifier
      else
        create_classifier
      end
    end

    def load_classifier
      json = File.read(@options[:model])
      data = JSON.parse(json)
      type = data['type']

      case type
      when 'bayes'
        Bayes.from_json(data)
      when 'lsi'
        LSI.from_json(data)
      when 'knn'
        KNN.from_json(data)
      when 'logistic_regression'
        LogisticRegression.from_json(data)
      else
        raise "Unknown classifier type in model: #{type}"
      end
    end

    def create_classifier
      type = CLASSIFIER_TYPES[@options[:type]] || :bayes

      case type
      when :lsi
        LSI.new(auto_rebuild: true)
      when :knn
        KNN.new(k: @options[:k], weighted: @options[:weighted])
      when :logistic_regression
        lr_opts = {} #: Hash[Symbol, untyped]
        lr_opts[:learning_rate] = @options[:learning_rate] if @options[:learning_rate]
        lr_opts[:regularization] = @options[:regularization] if @options[:regularization]
        lr_opts[:max_iterations] = @options[:max_iterations] if @options[:max_iterations]
        LogisticRegression.new(**lr_opts)
      else # :bayes or unknown defaults to Bayes
        Bayes.new
      end
    end

    def train_classifier(classifier, category, text)
      case classifier
      when Bayes, LogisticRegression
        classifier.add_category(category) unless classifier.categories.include?(category)
        text.each_line { |line| classifier.train(category, line.strip) unless line.strip.empty? }
      when LSI
        text.each_line do |line|
          next if line.strip.empty?

          classifier.add_item(line.strip, category.to_sym)
        end
      when KNN
        text.each_line do |line|
          next if line.strip.empty?

          classifier.add(category.to_sym => line.strip)
        end
      end
    end

    def train_lsi_from_files(classifier, category, files)
      files.each do |file|
        content = File.read(file)
        classifier.add_item(file, category.to_sym) { content }
      end
    end

    def save_classifier(classifier)
      classifier.storage = Storage::File.new(path: @options[:model])
      classifier.save
    end

    def classifier_type_name(classifier)
      case classifier
      when Bayes then 'bayes'
      when LSI then 'lsi'
      when KNN then 'knn'
      when LogisticRegression then 'logistic_regression'
      else 'unknown'
      end
    end

    def read_training_input
      if @args.any?
        @args.map { |file| File.read(file) }.join("\n")
      else
        read_stdin
      end
    end

    def read_stdin
      @stdin || ($stdin.tty? ? '' : $stdin.read)
    end

    def read_stdin_line
      (@stdin || ($stdin.tty? ? '' : $stdin.read)).to_s.strip
    end

    def read_stdin_lines
      read_stdin.to_s.split("\n").map(&:strip).reject(&:empty?)
    end

    # @rbs () -> void
    def show_getting_started
      @output << 'Classifier - Text classification from the command line'
      @output << ''
      @output << 'Get started by training some categories:'
      @output << ''
      @output << '  # Train from files'
      @output << '  classifier train spam spam_emails/*.txt'
      @output << '  classifier train ham good_emails/*.txt'
      @output << ''
      @output << '  # Train from stdin'
      @output << "  echo 'buy viagra now free pills cheap meds' | classifier train spam"
      @output << "  echo 'meeting scheduled for tomorrow to discuss project' | classifier train ham"
      @output << ''
      @output << 'Then classify text:'
      @output << ''
      @output << "  classifier 'free money buy now'"
      @output << "  classifier 'meeting postponed to friday'"
      @output << ''
      @output << 'Use LSI for semantic search:'
      @output << ''
      @output << "  echo 'ruby is a dynamic programming language' | classifier train docs -m lsi"
      @output << "  echo 'python is great for data science' | classifier train docs -m lsi"
      @output << "  classifier search 'programming'"
      @output << ''
      @output << 'Options:'
      @output << '  -f FILE    Model file (default: ./classifier.json)'
      @output << '  -m TYPE    Model type: bayes, lsi, knn, lr (default: bayes)'
      @output << '  -p         Show probabilities'
      @output << ''
      @output << 'Run "classifier --help" for full usage.'
    end
  end
end
