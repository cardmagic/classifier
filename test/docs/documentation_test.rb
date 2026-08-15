require_relative '../test_helper'

# Executes the code examples published in README.md and docs/*.md.
#
# Every assertion mirrors a value printed in the documentation. A failure here
# means the docs claim something the code no longer does. Fix the docs or the
# code, never the assertion alone.
module Docs
  class DocumentationTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
    end

    def teardown
      FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    end

    # --- README.md and docs/bayes.md ---------------------------------------

    def test_bayes_quick_start
      classifier = Classifier::Bayes.new(:spam, :ham)
      classifier.train(spam: 'Buy viagra cheap pills now')
      classifier.train(spam: 'You won million dollars prize')
      classifier.train(ham: ['Meeting tomorrow at 3pm', 'Quarterly report attached'])

      assert_equal 'Spam', classifier.classify('Cheap pills!')
      assert_equal %w[Spam Ham], classifier.categories
    end

    def test_bayes_classifications_are_negative_log_probabilities
      classifier = trained_bayes
      scores = classifier.classifications('Cheap pills!')

      assert_equal %w[Spam Ham], scores.keys
      assert_operator scores['Spam'], :>, scores['Ham']
      assert_operator scores['Spam'], :<, 0
    end

    def test_bayes_dynamic_training_methods
      classifier = Classifier::Bayes.new(:spam, :ham)
      classifier.train_spam('cheap pills')
      classifier.train_ham('meeting tomorrow')

      assert_equal 'Spam', classifier.classify('pills')
    end

    def test_bayes_category_management
      classifier = trained_bayes

      classifier.add_category(:other)

      assert_equal %w[Spam Ham Other], classifier.categories

      classifier.remove_category(:other)

      assert_equal %w[Spam Ham], classifier.categories
    end

    def test_bayes_accepts_an_array_of_categories
      assert_equal %w[Spam Ham], Classifier::Bayes.new(%i[spam ham]).categories
    end

    # --- README.md and docs/logistic-regression.md -------------------------

    def test_logistic_regression_requires_fit_before_classify
      classifier = untrained_logistic_regression

      assert_raises(Classifier::NotFittedError) { classifier.classify('I love it!') }
    end

    def test_logistic_regression_quick_start
      classifier = untrained_logistic_regression
      classifier.fit

      assert_predicate classifier, :fitted?
      assert_equal 'Positive', classifier.classify('I love it!')
    end

    def test_logistic_regression_probabilities_sum_to_one
      classifier = untrained_logistic_regression
      classifier.fit
      probabilities = classifier.probabilities('I love it!')

      assert_in_delta 1.0, probabilities.values.sum
      assert_operator probabilities['Positive'], :>, probabilities['Negative']
    end

    def test_logistic_regression_weights_rank_by_absolute_value
      classifier = untrained_logistic_regression
      classifier.fit
      weights = classifier.weights('positive')

      assert_includes weights.keys, :amaz
      assert_operator weights[:love], :>, 0
      assert_operator weights[:hate], :<, 0

      magnitudes = weights.values.map(&:abs)

      assert_equal magnitudes.sort.reverse, magnitudes
    end

    def test_logistic_regression_weights_limit_caps_the_count
      classifier = untrained_logistic_regression
      classifier.fit

      assert_equal 3, classifier.weights('positive', limit: 3).size
    end

    def test_logistic_regression_survives_a_round_trip_without_refitting
      classifier = untrained_logistic_regression
      classifier.fit
      path = File.join(@tmpdir, 'lr.json')
      classifier.save_to_file(path)

      loaded = Classifier::LogisticRegression.load_from_file(path)

      assert_equal 'Positive', loaded.classify('I love it!')
    end

    # --- README.md and docs/lsi.md -----------------------------------------

    def test_lsi_quick_start
      lsi = Classifier::LSI.new
      lsi.add(dog: 'dog puppy canine bark fetch', cat: 'cat kitten feline meow purr')

      assert_equal 'dog', lsi.classify('My puppy barks')
      assert_equal ['dog', 1.0], lsi.classify_with_confidence('My puppy barks')
    end

    def test_lsi_search_returns_documents_ranked_by_similarity
      lsi = Classifier::LSI.new
      lsi.add(dog: 'dog puppy canine bark fetch', cat: 'cat kitten feline meow purr')

      assert_equal 'dog puppy canine bark fetch', lsi.search('puppy', 2).first
      assert_equal 2, lsi.items.size
    end

    def test_lsi_manual_index_build
      lsi = Classifier::LSI.new(auto_rebuild: false)
      lsi.add(dog: 'dog puppy canine bark fetch')
      lsi.add(cat: 'cat kitten feline meow purr')
      lsi.build_index

      refute_predicate lsi, :needs_rebuild?
    end

    def test_lsi_incremental_mode_needs_manual_index_control
      lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false, max_rank: 100)
      lsi.add(tech: incremental_corpus)
      lsi.build_index

      assert_predicate lsi, :incremental_enabled?

      lsi.add(tech: 'Go is a fast compiled language for backend systems')

      assert_predicate lsi, :incremental_enabled?
      assert_equal 5, lsi.current_rank
    end

    def test_lsi_incremental_mode_never_starts_under_auto_rebuild
      lsi = Classifier::LSI.new(incremental: true)
      lsi.add(tech: incremental_corpus)
      lsi.build_index

      refute_predicate lsi, :incremental_enabled?
    end

    def test_lsi_highest_ranked_stems_are_distinct
      lsi = animal_lsi

      assert_equal %i[dog puppi canin],
                   lsi.highest_ranked_stems('dog puppy canine bark fetch loyal', 3)
    end

    def test_lsi_highest_relative_content_returns_documents
      result = animal_lsi.highest_relative_content(2)

      assert_kind_of Array, result
      assert_equal 2, result.size
    end

    def test_lsi_shovel_adds_without_a_category
      lsi = animal_lsi

      assert_equal 3, lsi.items.size
    end

    def test_lsi_add_batch
      lsi = Classifier::LSI.new
      lsi.add_batch(tech: ['Ruby is elegant', 'Python is popular'],
                    sports: ['soccer goal', 'basketball hoop'])

      assert_equal 4, lsi.items.size
    end

    def test_bayes_append_category_is_an_alias
      classifier = Classifier::Bayes.new(:spam)
      classifier.append_category(:ham)

      assert_equal %w[Spam Ham], classifier.categories
    end

    def test_lsi_backend_is_native_or_ruby
      assert_includes %i[native ruby], Classifier::LSI.backend
    end

    def test_string_summary
      text = 'The dog barks loudly. The cat sleeps quietly. ' \
             'Birds sing sweetly in the morning light.'

      assert_equal 'The cat sleeps quietly.', text.summary(1)
    end

    # --- README.md and docs/knn.md -----------------------------------------

    def test_knn_quick_start
      knn = trained_knn

      assert_equal 'tech', knn.classify('programming code')
      assert_equal %w[tech sports], knn.categories
    end

    def test_knn_classify_with_neighbors
      result = trained_knn.classify_with_neighbors('programming code')

      assert_equal 'tech', result[:category]
      assert_equal 3, result[:neighbors].size
      assert_equal({ 'tech' => 2.0, 'sports' => 1.0 }, result[:votes])
      assert_in_delta 2.0 / 3.0, result[:confidence]
    end

    def test_knn_train_is_an_alias_of_add
      knn = Classifier::KNN.new(k: 1)
      knn.train(tech: 'compiler')

      assert_equal ['tech'], knn.categories
    end

    def test_knn_exposes_and_updates_k
      knn = Classifier::KNN.new(k: 3)

      assert_equal 3, knn.k

      knn.k = 5

      assert_equal 5, knn.k
    end

    # --- README.md and docs/tfidf.md ---------------------------------------

    def test_tfidf_quick_start
      tfidf = Classifier::TFIDF.new
      tfidf.fit(['Ruby is great', 'Python is great', 'Ruby on Rails'])

      assert_equal({ rubi: 1.0 }, tfidf.transform('Ruby programming'))
      assert_predicate tfidf, :fitted?
    end

    def test_tfidf_raises_before_fit
      assert_raises(Classifier::NotFittedError) { Classifier::TFIDF.new.transform('Ruby') }
    end

    def test_tfidf_ngram_feature_names
      tfidf = Classifier::TFIDF.new(ngram_range: [1, 2])
      tfidf.fit(['machine learning rocks', 'machine learning is fun'])

      assert_equal %i[fun learn learn_fun learn_rock machin machin_learn],
                   tfidf.feature_names.sort.first(6)
    end

    def test_tfidf_exposes_document_frequency_bounds
      tfidf = Classifier::TFIDF.new(min_df: 2, max_df: 0.85)

      assert_equal 2, tfidf.min_df
      assert_in_delta 0.85, tfidf.max_df
    end

    def test_tfidf_fit_from_stream_counts_each_line_as_a_document
      tfidf = Classifier::TFIDF.new
      tfidf.fit_from_stream(Classifier::Streaming::MultiIO.new(corpus_paths))

      assert_equal 4, tfidf.num_documents
    end

    # --- docs/configuration.md ---------------------------------------------

    def test_word_hash_returns_stemmed_counts
      assert_equal({ rubi: 1, program: 1, eleg: 1 }, 'Ruby programming is elegant'.word_hash)
    end

    def test_stem_to_word_hash_maps_stems_to_whole_words
      mapping = 'Ruby programming is elegant and programming rocks'.stem_to_word_hash

      assert_equal({ rubi: 'ruby', program: 'programming', eleg: 'elegant', rock: 'rocks' }, mapping)
    end

    def test_default_min_word_length
      assert_equal 3, Classifier.config.min_word_length
    end

    def test_error_hierarchy
      assert_operator Classifier::NotFittedError, :<, Classifier::Error
      assert_operator Classifier::UnsavedChangesError, :<, Classifier::Error
      assert_operator Classifier::StorageError, :<, Classifier::Error
    end

    # --- docs/persistence.md -----------------------------------------------

    def test_save_and_load_a_file
      path = File.join(@tmpdir, 'model.json')
      trained_bayes.save_to_file(path)

      assert_equal 'Spam', Classifier::Bayes.load_from_file(path).classify('pills')
    end

    def test_file_storage_backend
      classifier = trained_bayes
      classifier.storage = Classifier::Storage::File.new(path: File.join(@tmpdir, 'model.json'))
      classifier.save

      loaded = Classifier::Bayes.load(storage: classifier.storage)

      assert_equal 'Spam', loaded.classify('pills')
    end

    def test_memory_storage_backend
      storage = Classifier::Storage::Memory.new
      classifier = Classifier::Bayes.new(:a, :b)
      classifier.train(a: 'alpha', b: 'beta')
      classifier.storage = storage
      classifier.save

      assert_equal %w[A B], Classifier::Bayes.load(storage: storage).categories
    end

    def test_storage_base_interface
      assert_equal %i[delete exists? read write],
                   Classifier::Storage::Base.instance_methods(false).sort
    end

    def test_marshal_round_trip
      restored = Marshal.load(Marshal.dump(trained_bayes))

      assert_equal 'Spam', restored.classify('pills')
    end

    # --- docs/streaming.md -------------------------------------------------

    def test_train_from_stream_with_progress
      classifier = Classifier::Bayes.new(:spam, :ham)
      seen = []
      classifier.train_from_stream(:spam, File.open(corpus_paths.first)) do |progress|
        seen << progress.completed
      end

      assert_equal %w[Spam Ham], classifier.categories
      refute_empty seen
    end

    def test_multi_io_reads_paths_in_order
      lines = Classifier::Streaming::MultiIO.new(corpus_paths).each_line.to_a

      assert_equal ["cheap pills now\n", "buy viagra cheap\n",
                    "meeting tomorrow\n", "quarterly report\n"], lines
    end

    def test_multi_io_accepts_io_objects
      lines = []
      Classifier::Streaming::MultiIO.new([File.open(corpus_paths.first)]).each_line { |l| lines << l }

      assert_equal ["cheap pills now\n", "buy viagra cheap\n"], lines
    end

    def test_multi_io_returns_an_enumerator_without_a_block
      assert_instance_of Enumerator, Classifier::Streaming::MultiIO.new(corpus_paths).each_line
    end

    def test_train_batch_accepts_an_array
      classifier = Classifier::Bayes.new(:spam, :ham)
      classifier.train_batch(:spam, ['cheap pills', 'you won a prize'])

      assert_equal 'Spam', classifier.classify('pills')
    end

    private

    def trained_bayes
      classifier = Classifier::Bayes.new(:spam, :ham)
      classifier.train(spam: 'Buy viagra cheap pills now')
      classifier.train(spam: 'You won million dollars prize')
      classifier.train(ham: ['Meeting tomorrow at 3pm', 'Quarterly report attached'])
      classifier
    end

    def untrained_logistic_regression
      classifier = Classifier::LogisticRegression.new(:positive, :negative)
      classifier.train(positive: 'love amazing great wonderful')
      classifier.train(negative: 'hate terrible awful bad')
      classifier
    end

    def trained_knn
      knn = Classifier::KNN.new(k: 3)
      %w[laptop coding software developer programming].each { |w| knn.add(tech: w) }
      %w[football basketball soccer goal team].each { |w| knn.add(sports: w) }
      knn
    end

    def animal_lsi
      lsi = Classifier::LSI.new
      lsi.add(dog: 'dog puppy canine bark fetch loyal',
              cat: 'cat kitten feline meow purr independent')
      lsi << 'bird sparrow robin fly nest feather'
      lsi
    end

    def incremental_corpus
      [
        'Ruby is an elegant programming language for web development',
        'Python is a popular programming language for data science',
        'JavaScript runs in browsers and powers modern web applications',
        'Java is a compiled language used for enterprise backend systems',
        'Rust provides memory safety without a garbage collector runtime'
      ]
    end

    def corpus_paths
      @corpus_paths ||= begin
        a = File.join(@tmpdir, 'a.txt')
        b = File.join(@tmpdir, 'b.txt')
        File.write(a, "cheap pills now\nbuy viagra cheap\n")
        File.write(b, "meeting tomorrow\nquarterly report\n")
        [a, b]
      end
    end
  end
end
