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

module Classifier
  # This class implements a Latent Semantic Indexer, which can search, classify and cluster
  # data based on underlying semantic relations. For more information on the algorithms used,
  # please consult Wikipedia[http://en.wikipedia.org/wiki/Latent_Semantic_Indexing].
  class LSI
    include Mutex_m

    # @rbs @auto_rebuild: bool
    # @rbs @word_list: WordList
    # @rbs @items: Hash[untyped, ContentNode]
    # @rbs @version: Integer
    # @rbs @built_at_version: Integer
    # @rbs @singular_values: Array[Float]?

    attr_reader :word_list, :singular_values
    attr_accessor :auto_rebuild

    # Create a fresh index.
    # If you want to call #build_index manually, use
    #      Classifier::LSI.new auto_rebuild: false
    #
    # @rbs (?Hash[Symbol, untyped]) -> void
    def initialize(options = {})
      super()
      @auto_rebuild = true unless options[:auto_rebuild] == false
      @word_list = WordList.new
      @items = {}
      @version = 0
      @built_at_version = -1
    end

    # Returns true if the index needs to be rebuilt.  The index needs
    # to be built after all informaton is added, but before you start
    # using it for search, classification and cluster detection.
    #
    # @rbs () -> bool
    def needs_rebuild?
      synchronize { (@items.keys.size > 1) && (@version != @built_at_version) }
    end

    # Returns the singular value spectrum for informed cutoff selection.
    # This helps users understand how much variance each dimension captures
    # and make informed decisions about the cutoff parameter.
    #
    # Returns nil if the index hasn't been built yet.
    #
    # Each entry in the returned array contains:
    # - :dimension - The dimension index (0-based)
    # - :value - The singular value
    # - :percentage - What percentage of total variance this dimension captures
    # - :cumulative_percentage - Cumulative variance captured up to this dimension
    #
    # Example usage for tuning:
    #   spectrum = lsi.singular_value_spectrum
    #   # Find how many dimensions capture 90% of variance
    #   dims_for_90 = spectrum.find_index { |e| e[:cumulative_percentage] >= 0.90 }
    #   optimal_cutoff = dims_for_90 ? (dims_for_90 + 1).to_f / spectrum.size : 0.99
    #
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

    # Adds an item to the index. item is assumed to be a string, but
    # any item may be indexed so long as it responds to #to_s or if
    # you provide an optional block explaining how the indexer can
    # fetch fresh string data. This optional block is passed the item,
    # so the item may only be a reference to a URL or file name.
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
      synchronize do
        @items[item] = ContentNode.new(clean_word_hash, *categories)
        @version += 1
      end
      build_index if @auto_rebuild
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
      synchronize do
        return unless @items.key?(item)

        @items.delete(item)
        @version += 1
      end
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
    # Cutoff tuning guide:
    # - Higher cutoff (0.9): Preserves more semantic dimensions, better for large diverse corpora
    # - Lower cutoff (0.5): More aggressive dimensionality reduction, better for noisy data
    # - Default (0.75): Reasonable middle ground for most use cases
    #
    # Use #singular_value_spectrum after building to analyze variance distribution
    # and make informed decisions about cutoff tuning.
    #
    # @rbs (?Float) -> void
    def build_index(cutoff = 0.75)
      validate_cutoff!(cutoff)

      synchronize do
        return unless needs_rebuild_unlocked?

        make_word_list

        doc_list = @items.values
        tda = doc_list.collect { |node| node.raw_vector_with(@word_list) }

        if self.class.native_available?
          # Convert vectors to arrays for matrix construction
          tda_arrays = tda.map { |v| v.respond_to?(:to_a) ? v.to_a : v }
          tdm = self.class.matrix_class.alloc(*tda_arrays).trans
          ntdm = build_reduced_matrix(tdm, cutoff)
          assign_native_ext_lsi_vectors(ntdm, doc_list)
        else
          tdm = Matrix.rows(tda).trans
          ntdm = build_reduced_matrix(tdm, cutoff)
          assign_ruby_lsi_vectors(ntdm, doc_list)
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
    # cutoff signifies the proportion of documents to consider when classifying
    # text. Must be between 0 and 1 (exclusive). A cutoff of 0.99 means nearly
    # every document in the index votes on what category the document is in.
    #
    # Cutoff tuning guide:
    # - Higher cutoff (0.5-0.9): More documents vote, smoother but slower classification
    # - Lower cutoff (0.1-0.3): Fewer documents vote, faster but may be noisier
    # - Default (0.30): Good balance for most classification tasks
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
      [@auto_rebuild, @word_list, @items, @version, @built_at_version]
    end

    # Custom marshal deserialization to recreate mutex
    # @rbs (Array[untyped]) -> void
    def marshal_load(data)
      mu_initialize
      @auto_rebuild, @word_list, @items, @version, @built_at_version = data
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

    # Saves the LSI index to a file.
    #
    # @rbs (String) -> Integer
    def save(path)
      File.write(path, to_json)
    end

    # Loads an LSI index from a file saved with #save.
    #
    # @rbs (String) -> LSI
    def self.load(path)
      from_json(File.read(path))
    end

    private

    # Validates that cutoff is within the valid range (0, 1) exclusive.
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
      cn
    end

    # @rbs (untyped, ?Float) -> untyped
    def build_reduced_matrix(matrix, cutoff = 0.75)
      # TODO: Check that M>=N on these dimensions! Transpose helps assure this
      u, v, s = matrix.SV_decomp

      # Store singular values (sorted descending) for introspection
      @singular_values = s.sort.reverse

      # Clamp index to 0 minimum to prevent negative indices with very small cutoffs
      # (e.g., cutoff=0.01 with size=3 would give (3*0.01).round-1 = -1)
      s_cutoff_index = [(s.size * cutoff).round - 1, 0].max
      s_cutoff = @singular_values[s_cutoff_index]
      s.size.times do |ord|
        s[ord] = 0.0 if s[ord] < s_cutoff
      end
      # Reconstruct the term document matrix, only with reduced rank
      result = u * self.class.matrix_class.diag(s) * v.trans

      # SVD may return transposed dimensions when row_size < column_size
      # Ensure result matches input dimensions
      result = result.trans if result.row_size != matrix.row_size

      result
    end

    # @rbs () -> void
    def make_word_list
      @word_list = WordList.new
      @items.each_value do |node|
        node.word_hash.each_key { |key| @word_list.add_word key }
      end
    end
  end
end
