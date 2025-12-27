# rbs_inline: enabled

# Author::    David Fayram  (mailto:dfayram@lensmen.net)
# Copyright:: Copyright (c) 2005 David Fayram II
# License::   LGPL

module Classifier
  class LSI
    # @rbs @gsl_available: bool
    @gsl_available = false

    class << self
      # @rbs @gsl_available: bool
      attr_accessor :gsl_available
    end
  end
end

begin
  # to test the native vector class, try `rake test NATIVE_VECTOR=true`
  raise LoadError if ENV['NATIVE_VECTOR'] == 'true'
  raise LoadError unless Gem::Specification.find_all_by_name('gsl').any?

  require 'gsl'
  require 'classifier/extensions/vector_serialize'
  Classifier::LSI.gsl_available = true
rescue LoadError
  unless ENV['SUPPRESS_GSL_WARNING'] == 'true'
    warn 'Notice: for 10x faster LSI, run `gem install gsl`. Set SUPPRESS_GSL_WARNING=true to hide this.'
  end
  Classifier::LSI.gsl_available = false
  require 'classifier/extensions/vector'
end

require 'classifier/lsi/word_list'
require 'classifier/lsi/content_node'
require 'classifier/lsi/summary'

module Classifier
  # This class implements a Latent Semantic Indexer, which can search, classify and cluster
  # data based on underlying semantic relations. For more information on the algorithms used,
  # please consult Wikipedia[http://en.wikipedia.org/wiki/Latent_Semantic_Indexing].
  class LSI
    # @rbs @auto_rebuild: bool
    # @rbs @word_list: WordList
    # @rbs @items: Hash[untyped, ContentNode]
    # @rbs @version: Integer
    # @rbs @built_at_version: Integer

    attr_reader :word_list
    attr_accessor :auto_rebuild

    # Create a fresh index.
    # If you want to call #build_index manually, use
    #      Classifier::LSI.new auto_rebuild: false
    #
    # @rbs (?Hash[Symbol, untyped]) -> void
    def initialize(options = {})
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
      (@items.keys.size > 1) && (@version != @built_at_version)
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
      @items[item] = ContentNode.new(clean_word_hash, *categories)
      @version += 1
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
      return [] unless @items[item]

      @items[item].categories
    end

    # Removes an item from the database, if it is indexed.
    #
    # @rbs (String) -> void
    def remove_item(item)
      return unless @items.key?(item)

      @items.delete(item)
      @version += 1
    end

    # Returns an array of items that are indexed.
    # @rbs () -> Array[untyped]
    def items
      @items.keys
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
    # @rbs (?Float) -> void
    def build_index(cutoff = 0.75)
      return unless needs_rebuild?

      make_word_list

      doc_list = @items.values
      tda = doc_list.collect { |node| node.raw_vector_with(@word_list) }

      if self.class.gsl_available
        tdm = GSL::Matrix.alloc(*tda).trans
        ntdm = build_reduced_matrix(tdm, cutoff)

        ntdm.size[1].times do |col|
          vec = GSL::Vector.alloc(ntdm.column(col)).row
          doc_list[col].lsi_vector = vec
          doc_list[col].lsi_norm = vec.normalize
        end
      else
        tdm = Matrix.rows(tda).trans
        ntdm = build_reduced_matrix(tdm, cutoff)

        ntdm.column_size.times do |col|
          next unless doc_list[col]

          column = ntdm.column(col)
          next unless column

          doc_list[col].lsi_vector = column
          doc_list[col].lsi_norm = column.normalize
        end
      end

      @built_at_version = @version
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
      return [] if needs_rebuild?

      avg_density = {}
      @items.each_key { |x| avg_density[x] = proximity_array_for_content(x).sum { |pair| pair[1] } }

      avg_density.keys.sort_by { |x| avg_density[x] }.reverse[0..(max_chunks - 1)].map
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
    def proximity_array_for_content(doc, &)
      return [] if needs_rebuild?

      content_node = node_for_content(doc, &)
      result =
        @items.keys.collect do |item|
          val = if self.class.gsl_available
                  content_node.search_vector * @items[item].search_vector.col
                else
                  (Matrix[content_node.search_vector] * @items[item].search_vector)[0]
                end
          [item, val]
        end
      result.sort_by { |x| x[1] }.reverse
    end

    # Similar to proximity_array_for_content, this function takes similar
    # arguments and returns a similar array. However, it uses the normalized
    # calculated vectors instead of their full versions. This is useful when
    # you're trying to perform operations on content that is much smaller than
    # the text you're working with. search uses this primitive.
    #
    # @rbs (String) ?{ (String) -> String } -> Array[[String, Float]]
    def proximity_norms_for_content(doc, &)
      return [] if needs_rebuild?

      content_node = node_for_content(doc, &)
      result =
        @items.keys.collect do |item|
          val = if self.class.gsl_available
                  content_node.search_norm * @items[item].search_norm.col
                else
                  (Matrix[content_node.search_norm] * @items[item].search_norm)[0]
                end
          [item, val]
        end
      result.sort_by { |x| x[1] }.reverse
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
      return [] if needs_rebuild?

      carry = proximity_norms_for_content(string)
      result = carry.collect { |x| x[0] }
      result[0..(max_nearest - 1)]
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
      carry =
        proximity_array_for_content(doc, &block).reject { |pair| pair[0] == doc }
      result = carry.collect { |x| x[0] }
      result[0..(max_nearest - 1)]
    end

    # This function uses a voting system to categorize documents, based on
    # the categories of other documents. It uses the same logic as the
    # find_related function to find related documents, then returns the
    # most obvious category from this list.
    #
    # cutoff signifies the number of documents to consider when clasifying
    # text. A cutoff of 1 means that every document in the index votes on
    # what category the document is in. This may not always make sense.
    #
    # @rbs (String, ?Float) ?{ (String) -> String } -> String | Symbol
    def classify(doc, cutoff = 0.30, &)
      votes = vote(doc, cutoff, &)

      ranking = votes.keys.sort_by { |x| votes[x] }
      ranking[-1]
    end

    # @rbs (String, ?Float) ?{ (String) -> String } -> Hash[String | Symbol, Float]
    def vote(doc, cutoff = 0.30, &)
      icutoff = (@items.size * cutoff).round
      carry = proximity_array_for_content(doc, &)
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
    def classify_with_confidence(doc, cutoff = 0.30, &)
      votes = vote(doc, cutoff, &)
      votes_sum = votes.values.sum
      return [nil, nil] if votes_sum.zero?

      ranking = votes.keys.sort_by { |x| votes[x] }
      winner = ranking[-1]
      vote_share = votes[winner] / votes_sum.to_f
      [winner, vote_share]
    end

    # Prototype, only works on indexed documents.
    # I have no clue if this is going to work, but in theory
    # it's supposed to.
    # @rbs (String, ?Integer) -> Array[Symbol]
    def highest_ranked_stems(doc, count = 3)
      raise 'Requested stem ranking on non-indexed content!' unless @items[doc]

      arr = node_for_content(doc).lsi_vector.to_a
      top_n = arr.sort.reverse[0..(count - 1)]
      top_n.collect { |x| @word_list.word_for_index(arr.index(x)) }
    end

    private

    # @rbs (untyped, ?Float) -> untyped
    def build_reduced_matrix(matrix, cutoff = 0.75)
      # TODO: Check that M>=N on these dimensions! Transpose helps assure this
      u, v, s = matrix.SV_decomp

      # TODO: Better than 75% term, please. :\
      s_cutoff = s.sort.reverse[(s.size * cutoff).round - 1]
      s.size.times do |ord|
        s[ord] = 0.0 if s[ord] < s_cutoff
      end
      # Reconstruct the term document matrix, only with reduced rank
      result = u * (self.class.gsl_available ? GSL::Matrix : ::Matrix).diag(s) * v.trans

      # Native Ruby SVD returns transposed dimensions when row_size < column_size
      # Ensure result matches input dimensions
      result = result.trans if !self.class.gsl_available && result.row_size != matrix.row_size

      result
    end

    # @rbs (String) ?{ (String) -> String } -> ContentNode
    def node_for_content(item, &block)
      return @items[item] if @items[item]

      clean_word_hash = block ? block.call(item).clean_word_hash : item.to_s.clean_word_hash
      cn = ContentNode.new(clean_word_hash, &block)
      cn.raw_vector_with(@word_list) unless needs_rebuild?
      cn
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
