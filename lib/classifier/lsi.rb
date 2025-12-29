# rbs_inline: enabled

# Author::    David Fayram  (mailto:dfayram@lensmen.net)
# Copyright:: Copyright (c) 2005 David Fayram II
# License::   LGPL

module Classifier
  class LSI
    # Backend options: :native, :ruby
    # @rbs @backend: Symbol
    @backend = :ruby

    class << self
      # @rbs @backend: Symbol
      attr_accessor :backend

      # Check if using native C extension
      # @rbs () -> bool
      def native_available?
        backend == :native
      end

      # Get the Vector class for the current backend
      # @rbs () -> Class
      def vector_class
        backend == :native ? Classifier::Linalg::Vector : ::Vector
      end

      # Get the Matrix class for the current backend
      # @rbs () -> Class
      def matrix_class
        backend == :native ? Classifier::Linalg::Matrix : ::Matrix
      end
    end
  end
end

# Backend detection: native extension > pure Ruby
# Set NATIVE_VECTOR=true to force pure Ruby implementation

begin
  raise LoadError if ENV['NATIVE_VECTOR'] == 'true'

  require 'classifier/classifier_ext'
  Classifier::LSI.backend = :native
rescue LoadError
  # Fall back to pure Ruby implementation
  unless ENV['SUPPRESS_LSI_WARNING'] == 'true'
    warn 'Notice: for 5-10x faster LSI, install the classifier gem with native extensions. ' \
         'Set SUPPRESS_LSI_WARNING=true to hide this.'
  end
  Classifier::LSI.backend = :ruby
  require 'classifier/extensions/vector'
end

require 'json'
require 'mutex_m'
require 'classifier/lsi/word_list'
require 'classifier/lsi/content_node'
require 'classifier/lsi/summary'
require 'classifier/lsi/incremental_svd'

module Classifier
  # This class implements a Latent Semantic Indexer, which can search, classify and cluster
  # data based on underlying semantic relations. For more information on the algorithms used,
  # please consult Wikipedia[http://en.wikipedia.org/wiki/Latent_Semantic_Indexing].
  class LSI
    include Mutex_m
    include Streaming

    # @rbs @auto_rebuild: bool
    # @rbs @word_list: WordList
    # @rbs @items: Hash[untyped, ContentNode]
    # @rbs @version: Integer
    # @rbs @built_at_version: Integer
    # @rbs @singular_values: Array[Float]?
    # @rbs @dirty: bool
    # @rbs @storage: Storage::Base?
    # @rbs @incremental_mode: bool
    # @rbs @u_matrix: Matrix?
    # @rbs @max_rank: Integer
    # @rbs @initial_vocab_size: Integer?

    attr_reader :word_list, :singular_values
    attr_accessor :auto_rebuild, :storage

    # Default maximum rank for incremental SVD
    DEFAULT_MAX_RANK = 100

    # Create a fresh index.
    # If you want to call #build_index manually, use
    #      Classifier::LSI.new auto_rebuild: false
    #
    # For incremental SVD mode (adds documents without full rebuild):
    #      Classifier::LSI.new incremental: true, max_rank: 100
    #
    # @rbs (?Hash[Symbol, untyped]) -> void
    def initialize(options = {})
      super()
      @auto_rebuild = true unless options[:auto_rebuild] == false
      @word_list = WordList.new
      @items = {}
      @version = 0
      @built_at_version = -1
      @dirty = false
      @storage = nil

      # Incremental SVD settings
      @incremental_mode = options[:incremental] == true
      @max_rank = options[:max_rank] || DEFAULT_MAX_RANK
      @u_matrix = nil
      @initial_vocab_size = nil
    end

    # Returns true if the index needs to be rebuilt.  The index needs
    # to be built after all informaton is added, but before you start
    # using it for search, classification and cluster detection.
    #
    # @rbs () -> bool
    def needs_rebuild?
      synchronize { (@items.keys.size > 1) && (@version != @built_at_version) }
    end

    # @rbs () -> Array[Hash[Symbol, untyped]]?
    def singular_value_spectrum
      return nil unless @singular_values

      total = @singular_values.sum
      return nil if total.zero?

      cumulative = 0.0
      @singular_values.map.with_index do |value, i|
        cumulative += value
        {
          dimension: i,
          value: value,
          percentage: value / total,
          cumulative_percentage: cumulative / total
        }
      end
    end

    # Returns true if incremental mode is enabled and active.
    # Incremental mode becomes active after the first build_index call.
    #
    # @rbs () -> bool
    def incremental_enabled?
      @incremental_mode && @u_matrix != nil
    end

    # Returns the current rank of the incremental SVD (number of singular values kept).
    # Returns nil if incremental mode is not active.
    #
    # @rbs () -> Integer?
    def current_rank
      @singular_values&.count { |v| v > 0 }
    end

    # Disables incremental mode. Subsequent adds will trigger full rebuilds.
    #
    # @rbs () -> void
    def disable_incremental_mode!
      @incremental_mode = false
      @u_matrix = nil
      @initial_vocab_size = nil
    end

    # Enables incremental mode with optional max_rank setting.
    # The next build_index call will store the U matrix for incremental updates.
    #
    # @rbs (?max_rank: Integer) -> void
    def enable_incremental_mode!(max_rank: DEFAULT_MAX_RANK)
      @incremental_mode = true
      @max_rank = max_rank
    end

    # Adds items to the index using hash-style syntax.
    # The hash keys are categories, and values are items (or arrays of items).
    #
    # For example:
    #   lsi = Classifier::LSI.new
    #   lsi.add("Dog" => "Dogs are loyal pets")
    #   lsi.add("Cat" => "Cats are independent")
    #   lsi.add(Bird: "Birds can fly")  # Symbol keys work too
    #
    # Multiple items with the same category:
    #   lsi.add("Dog" => ["Dogs are loyal", "Puppies are cute"])
    #
    # Batch operations with multiple categories:
    #   lsi.add(
    #     "Dog" => ["Dogs are loyal", "Puppies are cute"],
    #     "Cat" => ["Cats are independent", "Kittens are playful"]
    #   )
    #
    # @rbs (**untyped items) -> void
    def add(**items)
      items.each do |category, value|
        Array(value).each { |doc| add_item(doc, category.to_s) }
      end
    end

    # Adds an item to the index. item is assumed to be a string, but
    # any item may be indexed so long as it responds to #to_s or if
    # you provide an optional block explaining how the indexer can
    # fetch fresh string data. This optional block is passed the item,
    # so the item may only be a reference to a URL or file name.
    #
    # @deprecated Use {#add} instead for clearer hash-style syntax.
    #
    # For example:
    #   lsi = Classifier::LSI.new
    #   lsi.add_item "This is just plain text"
    #   lsi.add_item "/home/me/filename.txt" { |x| File.read x }
    #   ar = ActiveRecordObject.find( :all )
    #   lsi.add_item ar, *ar.categories { |x| ar.content }
    #
    # @rbs (String, *String | Symbol) ?{ (String) -> String } -> void
    def add_item(item, *categories, &block)
      clean_word_hash = block ? block.call(item).clean_word_hash : item.to_s.clean_word_hash
      node = nil

      synchronize do
        node = ContentNode.new(clean_word_hash, *categories)
        @items[item] = node
        @version += 1
        @dirty = true
      end

      # Use incremental update if enabled and we have a U matrix
      if @incremental_mode && @u_matrix
        perform_incremental_update(node, clean_word_hash)
      elsif @auto_rebuild
        build_index
      end
    end

    # A less flexible shorthand for add_item that assumes
    # you are passing in a string with no categorries. item
    # will be duck typed via to_s .
    #
    # @rbs (String) -> void
    def <<(item)
      add_item(item)
    end

    # Returns the categories for a given indexed items. You are free to add and remove
    # items from this as you see fit. It does not invalide an index to change its categories.
    #
    # @rbs (String) -> Array[String | Symbol]
    def categories_for(item)
      synchronize do
        return [] unless @items[item]

        @items[item].categories
      end
    end

    # Removes an item from the database, if it is indexed.
    #
    # @rbs (String) -> void
    def remove_item(item)
      removed = synchronize do
        next false unless @items.key?(item)

        @items.delete(item)
        @version += 1
        @dirty = true
        true
      end
      build_index if removed && @auto_rebuild
    end

    # Returns an array of items that are indexed.
    # @rbs () -> Array[untyped]
    def items
      synchronize { @items.keys }
    end

    # This function rebuilds the index if needs_rebuild? returns true.
    # For very large document spaces, this indexing operation may take some
    # time to complete, so it may be wise to place the operation in another
    # thread.
    #
    # As a rule, indexing will be fairly swift on modern machines until
    # you have well over 500 documents indexed, or have an incredibly diverse
    # vocabulary for your documents.
    #
    # The optional parameter "cutoff" is a tuning parameter. When the index is
    # built, a certain number of s-values are discarded from the system. The
    # cutoff parameter tells the indexer how many of these values to keep.
    # A value of 1 for cutoff means that no semantic analysis will take place,
    # turning the LSI class into a simple vector search engine.
    #
    # @rbs (?Float, ?force: bool) -> void
    def build_index(cutoff = 0.75, force: false)
      validate_cutoff!(cutoff)

      synchronize do
        return unless force || needs_rebuild_unlocked?

        make_word_list

        doc_list = @items.values
        tda = doc_list.collect { |node| node.raw_vector_with(@word_list) }

        if self.class.native_available?
          # Convert vectors to arrays for matrix construction
          tda_arrays = tda.map { |v| v.respond_to?(:to_a) ? v.to_a : v }
          tdm = self.class.matrix_class.alloc(*tda_arrays).trans
          ntdm, u_mat = build_reduced_matrix_with_u(tdm, cutoff)
          assign_native_ext_lsi_vectors(ntdm, doc_list)
        else
          tdm = Matrix.rows(tda).trans
          ntdm, u_mat = build_reduced_matrix_with_u(tdm, cutoff)
          assign_ruby_lsi_vectors(ntdm, doc_list)
        end

        # Store U matrix for incremental mode
        if @incremental_mode
          @u_matrix = u_mat
          @initial_vocab_size = @word_list.size
        end

        @built_at_version = @version
      end
    end

    # This method returns max_chunks entries, ordered by their average semantic rating.
    # Essentially, the average distance of each entry from all other entries is calculated,
    # the highest are returned.
    #
    # This can be used to build a summary service, or to provide more information about
    # your dataset's general content. For example, if you were to use categorize on the
    # results of this data, you could gather information on what your dataset is generally
    # about.
    #
    # @rbs (?Integer) -> Array[String]
    def highest_relative_content(max_chunks = 10)
      synchronize do
        return [] if needs_rebuild_unlocked?

        avg_density = {}
        @items.each_key { |x| avg_density[x] = proximity_array_for_content_unlocked(x).sum { |pair| pair[1] } }

        avg_density.keys.sort_by { |x| avg_density[x] }.reverse[0..(max_chunks - 1)].map
      end
    end

    # This function is the primitive that find_related and classify
    # build upon. It returns an array of 2-element arrays. The first element
    # of this array is a document, and the second is its "score", defining
    # how "close" it is to other indexed items.
    #
    # These values are somewhat arbitrary, having to do with the vector space
    # created by your content, so the magnitude is interpretable but not always
    # meaningful between indexes.
    #
    # The parameter doc is the content to compare. If that content is not
    # indexed, you can pass an optional block to define how to create the
    # text data. See add_item for examples of how this works.
    #
    # @rbs (String) ?{ (String) -> String } -> Array[[String, Float]]
    def proximity_array_for_content(doc, &block)
      synchronize { proximity_array_for_content_unlocked(doc, &block) }
    end

    # Similar to proximity_array_for_content, this function takes similar
    # arguments and returns a similar array. However, it uses the normalized
    # calculated vectors instead of their full versions. This is useful when
    # you're trying to perform operations on content that is much smaller than
    # the text you're working with. search uses this primitive.
    #
    # @rbs (String) ?{ (String) -> String } -> Array[[String, Float]]
    def proximity_norms_for_content(doc, &block)
      synchronize { proximity_norms_for_content_unlocked(doc, &block) }
    end

    # This function allows for text-based search of your index. Unlike other functions
    # like find_related and classify, search only takes short strings. It will also ignore
    # factors like repeated words. It is best for short, google-like search terms.
    # A search will first priortize lexical relationships, then semantic ones.
    #
    # While this may seem backwards compared to the other functions that LSI supports,
    # it is actually the same algorithm, just applied on a smaller document.
    #
    # @rbs (String, ?Integer) -> Array[String]
    def search(string, max_nearest = 3)
      synchronize do
        return [] if needs_rebuild_unlocked?

        carry = proximity_norms_for_content_unlocked(string)
        result = carry.collect { |x| x[0] }
        result[0..(max_nearest - 1)]
      end
    end

    # This function takes content and finds other documents
    # that are semantically "close", returning an array of documents sorted
    # from most to least relavant.
    # max_nearest specifies the number of documents to return. A value of
    # 0 means that it returns all the indexed documents, sorted by relavence.
    #
    # This is particularly useful for identifing clusters in your document space.
    # For example you may want to identify several "What's Related" items for weblog
    # articles, or find paragraphs that relate to each other in an essay.
    #
    # @rbs (String, ?Integer) ?{ (String) -> String } -> Array[String]
    def find_related(doc, max_nearest = 3, &block)
      synchronize do
        carry =
          proximity_array_for_content_unlocked(doc, &block).reject { |pair| pair[0] == doc }
        result = carry.collect { |x| x[0] }
        result[0..(max_nearest - 1)]
      end
    end

    # This function uses a voting system to categorize documents, based on
    # the categories of other documents. It uses the same logic as the
    # find_related function to find related documents, then returns the
    # most obvious category from this list.
    #
    # @rbs (String, ?Float) ?{ (String) -> String } -> String | Symbol
    def classify(doc, cutoff = 0.30, &block)
      validate_cutoff!(cutoff)

      synchronize do
        votes = vote_unlocked(doc, cutoff, &block)

        ranking = votes.keys.sort_by { |x| votes[x] }
        ranking[-1]
      end
    end

    # @rbs (String, ?Float) ?{ (String) -> String } -> Hash[String | Symbol, Float]
    def vote(doc, cutoff = 0.30, &block)
      validate_cutoff!(cutoff)

      synchronize { vote_unlocked(doc, cutoff, &block) }
    end

    # Returns the same category as classify() but also returns
    # a confidence value derived from the vote share that the
    # winning category got.
    #
    # e.g.
    # category,confidence = classify_with_confidence(doc)
    # if confidence < 0.3
    #   category = nil
    # end
    #
    # See classify() for argument docs
    # @rbs (String, ?Float) ?{ (String) -> String } -> [String | Symbol | nil, Float?]
    def classify_with_confidence(doc, cutoff = 0.30, &block)
      validate_cutoff!(cutoff)

      synchronize do
        votes = vote_unlocked(doc, cutoff, &block)
        votes_sum = votes.values.sum
        return [nil, nil] if votes_sum.zero?

        ranking = votes.keys.sort_by { |x| votes[x] }
        winner = ranking[-1]
        vote_share = votes[winner] / votes_sum.to_f
        [winner, vote_share]
      end
    end

    # Prototype, only works on indexed documents.
    # I have no clue if this is going to work, but in theory
    # it's supposed to.
    # @rbs (String, ?Integer) -> Array[Symbol]
    def highest_ranked_stems(doc, count = 3)
      synchronize do
        raise 'Requested stem ranking on non-indexed content!' unless @items[doc]

        arr = node_for_content_unlocked(doc).lsi_vector.to_a
        top_n = arr.sort.reverse[0..(count - 1)]
        top_n.collect { |x| @word_list.word_for_index(arr.index(x)) }
      end
    end

    # Custom marshal serialization to exclude mutex state
    # @rbs () -> Array[untyped]
    def marshal_dump
      [@auto_rebuild, @word_list, @items, @version, @built_at_version, @dirty]
    end

    # Custom marshal deserialization to recreate mutex
    # @rbs (Array[untyped]) -> void
    def marshal_load(data)
      mu_initialize
      @auto_rebuild, @word_list, @items, @version, @built_at_version, @dirty = data
      @storage = nil
    end

    # Returns a hash representation of the LSI index.
    # Only source data (word_hash, categories) is included, not computed vectors.
    # This can be converted to JSON or used directly.
    #
    # @rbs () -> untyped
    def as_json(*)
      items_data = @items.transform_values do |node|
        {
          word_hash: node.word_hash.transform_keys(&:to_s),
          categories: node.categories.map(&:to_s)
        }
      end

      {
        version: 1,
        type: 'lsi',
        auto_rebuild: @auto_rebuild,
        items: items_data
      }
    end

    # Serializes the LSI index to a JSON string.
    # Only source data (word_hash, categories) is serialized, not computed vectors.
    # On load, the index will be rebuilt automatically.
    #
    # @rbs () -> String
    def to_json(*)
      as_json.to_json
    end

    # Loads an LSI index from a JSON string or Hash created by #to_json or #as_json.
    # The index will be rebuilt after loading.
    #
    # @rbs (String | Hash[String, untyped]) -> LSI
    def self.from_json(json)
      data = json.is_a?(String) ? JSON.parse(json) : json
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'lsi'

      # Create instance with auto_rebuild disabled during loading
      instance = new(auto_rebuild: false)

      # Restore items (categories stay as strings, matching original storage)
      data['items'].each do |item_key, item_data|
        word_hash = item_data['word_hash'].transform_keys(&:to_sym)
        categories = item_data['categories']
        instance.instance_variable_get(:@items)[item_key] = ContentNode.new(word_hash, *categories)
        instance.instance_variable_set(:@version, instance.instance_variable_get(:@version) + 1)
      end

      # Restore auto_rebuild setting and rebuild index
      instance.auto_rebuild = data['auto_rebuild']
      instance.build_index
      instance
    end

    # Saves the LSI index to the configured storage.
    # Raises ArgumentError if no storage is configured.
    #
    # @rbs () -> void
    def save
      raise ArgumentError, 'No storage configured. Use save_to_file(path) or set storage=' unless storage

      storage.write(to_json)
      @dirty = false
    end

    # Saves the LSI index to a file (legacy API).
    #
    # @rbs (String) -> Integer
    def save_to_file(path)
      result = File.write(path, to_json)
      @dirty = false
      result
    end

    # Reloads the LSI index from the configured storage.
    # Raises UnsavedChangesError if there are unsaved changes.
    # Use reload! to force reload and discard changes.
    #
    # @rbs () -> self
    def reload
      raise ArgumentError, 'No storage configured' unless storage
      raise UnsavedChangesError, 'Unsaved changes would be lost. Call save first or use reload!' if @dirty

      data = storage.read
      raise StorageError, 'No saved state found' unless data

      restore_from_json(data)
      @dirty = false
      self
    end

    # Force reloads the LSI index from storage, discarding any unsaved changes.
    #
    # @rbs () -> self
    def reload!
      raise ArgumentError, 'No storage configured' unless storage

      data = storage.read
      raise StorageError, 'No saved state found' unless data

      restore_from_json(data)
      @dirty = false
      self
    end

    # Returns true if there are unsaved changes.
    #
    # @rbs () -> bool
    def dirty?
      @dirty
    end

    # Loads an LSI index from the configured storage.
    # The storage is set on the returned instance.
    #
    # @rbs (storage: Storage::Base) -> LSI
    def self.load(storage:)
      data = storage.read
      raise StorageError, 'No saved state found' unless data

      instance = from_json(data)
      instance.storage = storage
      instance
    end

    # Loads an LSI index from a file (legacy API).
    #
    # @rbs (String) -> LSI
    def self.load_from_file(path)
      from_json(File.read(path))
    end

    # Loads an LSI index from a checkpoint.
    #
    # @rbs (storage: Storage::Base, checkpoint_id: String) -> LSI
    def self.load_checkpoint(storage:, checkpoint_id:)
      raise ArgumentError, 'Storage must be File storage for checkpoints' unless storage.is_a?(Storage::File)

      dir = File.dirname(storage.path)
      base = File.basename(storage.path, '.*')
      ext = File.extname(storage.path)
      checkpoint_path = File.join(dir, "#{base}_checkpoint_#{checkpoint_id}#{ext}")

      checkpoint_storage = Storage::File.new(path: checkpoint_path)
      instance = load(storage: checkpoint_storage)
      instance.storage = storage
      instance
    end

    # Trains the LSI index from an IO stream.
    # Each line in the stream is treated as a separate document.
    # Documents are added without rebuilding, then the index is rebuilt at the end.
    #
    # @example Train from a file
    #   lsi.train_from_stream(:category, File.open('corpus.txt'))
    #
    # @example With progress tracking
    #   lsi.train_from_stream(:category, io, batch_size: 500) do |progress|
    #     puts "#{progress.completed} documents processed"
    #   end
    #
    # @rbs (String | Symbol, IO, ?batch_size: Integer) { (Streaming::Progress) -> void } -> void
    def train_from_stream(category, io, batch_size: Streaming::DEFAULT_BATCH_SIZE, &block)
      original_auto_rebuild = @auto_rebuild
      @auto_rebuild = false

      begin
        reader = Streaming::LineReader.new(io, batch_size: batch_size)
        total = reader.estimate_line_count
        progress = Streaming::Progress.new(total: total)

        reader.each_batch do |batch|
          batch.each { |text| add_item(text, category) }
          progress.completed += batch.size
          progress.current_batch += 1
          yield progress if block_given?
        end
      ensure
        @auto_rebuild = original_auto_rebuild
        build_index if original_auto_rebuild
      end
    end

    # Adds items to the index in batches from an array.
    # Documents are added without rebuilding, then the index is rebuilt at the end.
    #
    # @example Batch add with progress
    #   lsi.add_batch(Dog: documents, batch_size: 100) do |progress|
    #     puts "#{progress.percent}% complete"
    #   end
    #
    # @rbs (?batch_size: Integer, **Array[String]) { (Streaming::Progress) -> void } -> void
    def add_batch(batch_size: Streaming::DEFAULT_BATCH_SIZE, **items, &block)
      original_auto_rebuild = @auto_rebuild
      @auto_rebuild = false

      begin
        total_docs = items.values.sum { |v| Array(v).size }
        progress = Streaming::Progress.new(total: total_docs)

        items.each do |category, documents|
          Array(documents).each_slice(batch_size) do |batch|
            batch.each { |doc| add_item(doc, category.to_s) }
            progress.completed += batch.size
            progress.current_batch += 1
            yield progress if block_given?
          end
        end
      ensure
        @auto_rebuild = original_auto_rebuild
        build_index if original_auto_rebuild
      end
    end

    # Alias train_batch to add_batch for API consistency with other classifiers.
    # Note: LSI uses categories differently (items have categories, not the training call).
    #
    # @rbs (?(String | Symbol), ?Array[String], ?batch_size: Integer, **Array[String]) { (Streaming::Progress) -> void } -> void
    def train_batch(category = nil, documents = nil, batch_size: Streaming::DEFAULT_BATCH_SIZE, **categories, &block)
      if category && documents
        add_batch(batch_size: batch_size, **{ category.to_sym => documents }, &block)
      else
        add_batch(batch_size: batch_size, **categories, &block)
      end
    end

    private

    # Restores LSI state from a JSON string (used by reload)
    # @rbs (String) -> void
    def restore_from_json(json)
      data = JSON.parse(json)
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'lsi'

      synchronize do
        # Recreate the items
        @items = {}
        data['items'].each do |item_key, item_data|
          word_hash = item_data['word_hash'].transform_keys(&:to_sym)
          categories = item_data['categories']
          @items[item_key] = ContentNode.new(word_hash, *categories)
        end

        # Restore settings
        @auto_rebuild = data['auto_rebuild']
        @version += 1
        @built_at_version = -1
        @word_list = WordList.new
        @dirty = false
      end

      # Rebuild the index
      build_index
    end

    # @rbs (Float) -> void
    def validate_cutoff!(cutoff)
      return if cutoff.positive? && cutoff < 1

      raise ArgumentError, "cutoff must be between 0 and 1 (exclusive), got #{cutoff}"
    end

    # Assigns LSI vectors using native C extension
    # @rbs (untyped, Array[ContentNode]) -> void
    def assign_native_ext_lsi_vectors(ntdm, doc_list)
      ntdm.size[1].times do |col|
        vec = self.class.vector_class.alloc(ntdm.column(col).to_a).row
        doc_list[col].lsi_vector = vec
        doc_list[col].lsi_norm = vec.normalize
      end
    end

    # Assigns LSI vectors using pure Ruby Matrix
    # @rbs (untyped, Array[ContentNode]) -> void
    def assign_ruby_lsi_vectors(ntdm, doc_list)
      ntdm.column_size.times do |col|
        next unless doc_list[col]

        column = ntdm.column(col)
        next unless column

        doc_list[col].lsi_vector = column
        doc_list[col].lsi_norm = column.normalize
      end
    end

    # Unlocked version of needs_rebuild? for internal use when lock is already held
    # @rbs () -> bool
    def needs_rebuild_unlocked?
      (@items.keys.size > 1) && (@version != @built_at_version)
    end

    # Unlocked version of proximity_array_for_content for internal use
    # @rbs (String) ?{ (String) -> String } -> Array[[String, Float]]
    def proximity_array_for_content_unlocked(doc, &)
      return [] if needs_rebuild_unlocked?
      return @items.keys.map { |item| [item, 1.0] } if @items.size == 1

      content_node = node_for_content_unlocked(doc, &)
      result =
        @items.keys.collect do |item|
          val = if self.class.native_available?
                  content_node.search_vector * @items[item].search_vector.col
                else
                  (Matrix[content_node.search_vector] * @items[item].search_vector)[0]
                end
          [item, val]
        end
      result.sort_by { |x| x[1] }.reverse
    end

    # Unlocked version of proximity_norms_for_content for internal use
    # @rbs (String) ?{ (String) -> String } -> Array[[String, Float]]
    def proximity_norms_for_content_unlocked(doc, &)
      return [] if needs_rebuild_unlocked?

      content_node = node_for_content_unlocked(doc, &)
      result =
        @items.keys.collect do |item|
          val = if self.class.native_available?
                  content_node.search_norm * @items[item].search_norm.col
                else
                  (Matrix[content_node.search_norm] * @items[item].search_norm)[0]
                end
          [item, val]
        end
      result.sort_by { |x| x[1] }.reverse
    end

    # Unlocked version of vote for internal use
    # @rbs (String, ?Float) ?{ (String) -> String } -> Hash[String | Symbol, Float]
    def vote_unlocked(doc, cutoff = 0.30, &)
      icutoff = (@items.size * cutoff).round
      carry = proximity_array_for_content_unlocked(doc, &)
      carry = carry[0..(icutoff - 1)]
      votes = {}
      carry.each do |pair|
        categories = @items[pair[0]].categories
        categories.each do |category|
          votes[category] ||= 0.0
          votes[category] += pair[1]
        end
      end
      votes
    end

    # Unlocked version of node_for_content for internal use
    # @rbs (String) ?{ (String) -> String } -> ContentNode
    def node_for_content_unlocked(item, &block)
      return @items[item] if @items[item]

      clean_word_hash = block ? block.call(item).clean_word_hash : item.to_s.clean_word_hash
      cn = ContentNode.new(clean_word_hash, &block)
      cn.raw_vector_with(@word_list) unless needs_rebuild_unlocked?

      # If incremental mode is active, we need to project the query document
      # onto the U matrix to get consistent LSI vectors
      if incremental_enabled?
        assign_lsi_vector_incremental(cn)
      end

      cn
    end

    # @rbs (untyped, ?Float) -> untyped
    def build_reduced_matrix(matrix, cutoff = 0.75)
      result, _u = build_reduced_matrix_with_u(matrix, cutoff)
      result
    end

    # Builds reduced matrix and returns both the result and the U matrix
    # U matrix is needed for incremental SVD updates
    # @rbs (untyped, ?Float) -> [untyped, Matrix]
    def build_reduced_matrix_with_u(matrix, cutoff = 0.75)
      # TODO: Check that M>=N on these dimensions! Transpose helps assure this
      u, v, s = matrix.SV_decomp

      all_singular_values = s.sort.reverse

      s_cutoff_index = [(s.size * cutoff).round - 1, 0].max
      s_cutoff = all_singular_values[s_cutoff_index]

      # Track which singular values are kept and their values
      kept_indices = []
      kept_singular_values = []
      s.size.times do |ord|
        if s[ord] >= s_cutoff
          kept_indices << ord
          kept_singular_values << s[ord]
        else
          s[ord] = 0.0
        end
      end

      # Sort kept singular values in descending order (same order as U columns will be)
      # kept_indices are sorted by value in extract_reduced_u, so we need to match
      @singular_values = kept_singular_values.sort.reverse

      # Reconstruct the term document matrix, only with reduced rank
      result = u * self.class.matrix_class.diag(s) * v.trans

      # SVD may return transposed dimensions when row_size < column_size
      # Ensure result matches input dimensions
      result = result.trans if result.row_size != matrix.row_size

      # Extract U matrix with only kept columns (non-zero singular values)
      # Convert to pure Ruby Matrix for incremental updates
      u_reduced = extract_reduced_u(u, kept_indices, s)

      [result, u_reduced]
    end

    # Extracts columns from U corresponding to kept singular values
    # Columns are sorted by descending singular value to match @singular_values order
    # @rbs (untyped, Array[Integer], Array[Float]) -> Matrix
    def extract_reduced_u(u, kept_indices, singular_values)
      return Matrix.empty(u.row_size, 0) if kept_indices.empty?

      # Sort indices by their singular values in descending order
      sorted_indices = kept_indices.sort_by { |i| -singular_values[i] }

      # Convert to Ruby Matrix if using native backend
      if u.respond_to?(:to_ruby_matrix)
        u = u.to_ruby_matrix
      elsif !u.is_a?(::Matrix)
        # Native matrix - extract columns manually
        rows = u.row_size.times.map do |i|
          sorted_indices.map { |j| u[i, j] }
        end
        return Matrix.rows(rows)
      end

      # Extract only the columns we need, sorted by singular value
      cols = sorted_indices.map { |i| u.column(i).to_a }
      Matrix.columns(cols)
    end

    # @rbs () -> void
    def make_word_list
      @word_list = WordList.new
      @items.each_value do |node|
        node.word_hash.each_key { |key| @word_list.add_word key }
      end
    end

    # Performs incremental SVD update for a new document
    # @rbs (ContentNode, Hash[Symbol, Integer]) -> void
    def perform_incremental_update(node, word_hash)
      needs_full_rebuild = false
      old_rank = nil

      synchronize do
        # Check for vocabulary growth that would require full rebuild
        if vocabulary_growth_exceeds_threshold?(word_hash)
          disable_incremental_mode!
          needs_full_rebuild = true
        else
          old_rank = @u_matrix.column_size

          # Extend vocabulary and U matrix for new words
          extend_vocabulary_for_incremental(word_hash)

          # Build raw vector for the new document
          raw_vec = node.raw_vector_with(@word_list)

          # Convert to Ruby Vector for incremental SVD
          raw_vector = Vector[*raw_vec.to_a]

          # Perform incremental SVD update
          @u_matrix, @singular_values = IncrementalSVD.update(
            @u_matrix,
            @singular_values,
            raw_vector,
            max_rank: @max_rank
          )

          new_rank = @u_matrix.column_size

          # If rank grew, we need to re-project all existing documents
          # to ensure consistent LSI vector sizes
          if new_rank > old_rank
            reproject_all_documents
          else
            # Only assign LSI vector to the new document
            assign_lsi_vector_incremental(node)
          end

          @built_at_version = @version
        end
      end

      # Call build_index outside the synchronized block to avoid deadlock
      build_index if needs_full_rebuild
    end

    # Checks if vocabulary growth would exceed threshold (20%)
    # @rbs (Hash[Symbol, Integer]) -> bool
    def vocabulary_growth_exceeds_threshold?(word_hash)
      return false unless @initial_vocab_size && @initial_vocab_size.positive?

      new_words = word_hash.keys.count { |w| @word_list[w].nil? }
      growth_ratio = new_words.to_f / @initial_vocab_size
      growth_ratio > 0.2
    end

    # Extends vocabulary and U matrix for new words
    # @rbs (Hash[Symbol, Integer]) -> void
    def extend_vocabulary_for_incremental(word_hash)
      new_words = word_hash.keys.select { |w| @word_list[w].nil? }
      return if new_words.empty?

      # Add new words to vocabulary
      new_words.each { |word| @word_list.add_word(word) }

      # Extend U matrix with zero rows for new terms
      extend_u_matrix(new_words.size)
    end

    # Extends U matrix with zero rows for new vocabulary terms
    # @rbs (Integer) -> void
    def extend_u_matrix(num_new_rows)
      return if num_new_rows.zero? || @u_matrix.nil?

      if self.class.native_available? && @u_matrix.is_a?(self.class.matrix_class)
        # Use native vstack for performance
        new_rows = self.class.matrix_class.zeros(num_new_rows, @u_matrix.column_size)
        @u_matrix = self.class.matrix_class.vstack(@u_matrix, new_rows)
      else
        # Pure Ruby fallback
        new_rows = Matrix.zero(num_new_rows, @u_matrix.column_size)
        @u_matrix = Matrix.vstack(@u_matrix, new_rows)
      end
    end

    # Re-projects all documents onto the current U matrix
    # Called when rank grows to ensure consistent LSI vector sizes
    # Uses native batch_project for performance when available
    # @rbs () -> void
    def reproject_all_documents
      return unless @u_matrix

      if self.class.native_available? && @u_matrix.respond_to?(:batch_project)
        reproject_all_documents_native
      else
        reproject_all_documents_ruby
      end
    end

    # Native batch re-projection using C extension
    # @rbs () -> void
    def reproject_all_documents_native
      # Collect raw vectors for all documents
      nodes = @items.values
      raw_vectors = nodes.map do |node|
        raw = node.raw_vector_with(@word_list)
        # Ensure we have native vectors
        if raw.is_a?(self.class.vector_class)
          raw
        else
          self.class.vector_class.alloc(raw.to_a)
        end
      end

      # Batch project all at once (much faster than individual projections)
      lsi_vectors = @u_matrix.batch_project(raw_vectors)

      # Assign results
      nodes.each_with_index do |node, i|
        lsi_vec = lsi_vectors[i].row
        node.lsi_vector = lsi_vec
        node.lsi_norm = lsi_vec.normalize
      end
    end

    # Pure Ruby re-projection (fallback)
    # @rbs () -> void
    def reproject_all_documents_ruby
      @items.each_value do |node|
        assign_lsi_vector_incremental(node)
      end
    end

    # Assigns LSI vector to a node using projection: lsi_vec = U^T * raw_vec
    # @rbs (ContentNode) -> void
    def assign_lsi_vector_incremental(node)
      return unless @u_matrix

      raw_vec = node.raw_vector_with(@word_list)
      raw_vector = Vector[*raw_vec.to_a]

      # LSI vector = U^T * raw_vector (projection into semantic space)
      lsi_arr = (@u_matrix.transpose * raw_vector).to_a

      # Use the appropriate vector class based on backend
      if self.class.native_available?
        lsi_vec = self.class.vector_class.alloc(lsi_arr).row
        node.lsi_vector = lsi_vec
        node.lsi_norm = lsi_vec.normalize
      else
        lsi_vec = Vector[*lsi_arr]
        node.lsi_vector = lsi_vec
        node.lsi_norm = lsi_vec.normalize
      end
    end
  end
end
