require_relative '../test_helper'

class LSITest < Minitest::Test
  def setup
    # we repeat principle words to help weight them.
    # This test is rather delicate, since this system is mostly noise.
    @str1 = 'This text deals with dogs. Dogs.'
    @str2 = 'This text involves dogs too. Dogs! '
    @str3 = 'This text revolves around cats. Cats.'
    @str4 = 'This text also involves cats. Cats!'
    @str5 = 'This text involves birds. Birds.'
  end

  def test_basic_indexing
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    refute_predicate lsi, :needs_rebuild?

    # NOTE: that the closest match to str1 is str2, even though it is not
    # the closest text match.
    assert_equal [@str2, @str5, @str3], lsi.find_related(@str1, 3)
  end

  def test_not_auto_rebuild
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    assert_predicate lsi, :needs_rebuild?
    lsi.build_index

    refute_predicate lsi, :needs_rebuild?
  end

  def test_basic_categorizing
    lsi = Classifier::LSI.new
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    assert_equal 'Dog', lsi.classify(@str1)
    assert_equal 'Cat', lsi.classify(@str3)
    assert_equal 'Bird', lsi.classify(@str5)
    assert_equal 'Bird', lsi.classify('Bird me to Bird')
  end

  def test_external_classifying
    lsi = Classifier::LSI.new
    bayes = Classifier::Bayes.new 'Dog', 'Cat', 'Bird'
    lsi.add_item @str1, 'Dog'
    bayes.train_dog @str1
    lsi.add_item @str2, 'Dog'
    bayes.train_dog @str2
    lsi.add_item @str3, 'Cat'
    bayes.train_cat @str3
    lsi.add_item @str4, 'Cat'
    bayes.train_cat @str4
    lsi.add_item @str5, 'Bird'
    bayes.train_bird @str5

    # We're talking about dogs. Even though the text matches the corpus on
    # cats better.  Dogs have more semantic weight than cats. So bayes
    # will fail here, but the LSI recognizes content.
    tricky_case = 'This text revolves around dogs.'

    assert_equal 'Dog', lsi.classify(tricky_case)
    assert_equal 'Cat', bayes.classify(tricky_case)
  end

  def test_recategorize_interface
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    tricky_case = 'This text revolves around dogs.'

    assert_equal 'Dog', lsi.classify(tricky_case)

    # Recategorize as needed.
    lsi.categories_for(@str1).clear.push 'Cow'
    lsi.categories_for(@str2).clear.push 'Cow'

    refute_predicate lsi, :needs_rebuild?
    assert_equal 'Cow', lsi.classify(tricky_case)
  end

  def test_classify_with_confidence
    lsi = Classifier::LSI.new
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    category, confidence = lsi.classify_with_confidence(@str1)

    assert_equal 'Dog', category
    assert_operator confidence, :>, 0.5, "Confidence should be greater than 0.5, but was #{confidence}"

    category, confidence = lsi.classify_with_confidence(@str3)

    assert_equal 'Cat', category
    assert_operator confidence, :>, 0.5, "Confidence should be greater than 0.5, but was #{confidence}"

    category, confidence = lsi.classify_with_confidence(@str5)

    assert_equal 'Bird', category
    assert_operator confidence, :>, 0.5, "Confidence should be greater than 0.5, but was #{confidence}"

    tricky_case = 'This text revolves around dogs.'
    category, confidence = lsi.classify_with_confidence(tricky_case)

    assert_equal 'Dog', category
    assert_operator confidence, :>, 0.3, "Confidence should be greater than 0.3, but was #{confidence}"
  end

  def test_search
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    # Searching by content and text, note that @str2 comes up first, because
    # both "dog" and "involve" are present. But, the next match is @str1 instead
    # of @str4, because "dog" carries more weight than involves.
    assert_equal([@str2, @str1, @str4, @str5, @str3],
                 lsi.search('dog involves', 100))

    # Keyword search shows how the space is mapped out in relation to
    # dog when magnitude is remove. Note the relations. We move from dog
    # through involve and then finally to other words.
    assert_equal([@str1, @str2, @str4, @str5, @str3],
                 lsi.search('dog', 5))
  end

  def test_serialize_safe
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    lsi_md = Marshal.dump lsi
    lsi_m = Marshal.load lsi_md

    assert_equal lsi_m.search('cat', 3), lsi.search('cat', 3)
    assert_equal lsi_m.find_related(@str1, 3), lsi.find_related(@str1, 3)
  end

  def test_keyword_search
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    assert_equal %i[dog text deal], lsi.highest_ranked_stems(@str1)
  end

  def test_summary
    assert_equal 'This text involves dogs too [...] This text also involves cats',
                 [@str1, @str2, @str3, @str4, @str5].join.summary(2)
  end

  # Edge case tests

  def test_empty_index_needs_rebuild
    lsi = Classifier::LSI.new

    refute_predicate lsi, :needs_rebuild?, 'Empty index should not need rebuild'
  end

  def test_single_item_needs_rebuild
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item 'Single document', 'Category'

    refute_predicate lsi, :needs_rebuild?, 'Single item index should not need rebuild'
  end

  def test_remove_item
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    assert_equal 2, lsi.items.size

    lsi.remove_item @str1

    assert_equal 1, lsi.items.size
    refute_includes lsi.items, @str1
  end

  def test_remove_nonexistent_item
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'

    lsi.remove_item 'nonexistent'

    assert_equal 1, lsi.items.size, 'Should not affect index when removing nonexistent item'
  end

  def test_remove_item_triggers_needs_rebuild
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.build_index

    refute_predicate lsi, :needs_rebuild?, 'Index should be current after build'

    lsi.remove_item @str1

    assert_predicate lsi, :needs_rebuild?, 'Index should need rebuild after removing item'
  end

  def test_items_method
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Cat'

    items = lsi.items

    assert_equal 2, items.size
    assert_includes items, @str1
    assert_includes items, @str2
  end

  def test_find_related_excludes_self
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    result = lsi.find_related(@str1, 3)

    refute_includes result, @str1, 'Should not include the source document in related results'
  end

  def test_unicode_mixed_with_ascii
    lsi = Classifier::LSI.new
    lsi.add_item 'English words and text here', 'English'
    lsi.add_item 'More english content available', 'English'
    lsi.add_item 'French words bonjour merci', 'French'

    result = lsi.classify('english content')

    assert_equal 'English', result
  end

  def test_needs_rebuild_with_auto_rebuild_true
    lsi = Classifier::LSI.new auto_rebuild: true
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    refute_predicate lsi, :needs_rebuild?, 'Auto-rebuild should keep index current'
  end

  def test_categories_for_nonexistent_item
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'

    result = lsi.categories_for('nonexistent')

    assert_empty result, 'Should return empty array for nonexistent item'
  end
end
