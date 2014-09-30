require File.dirname(__FILE__) + '/../test_helper'
class LSITest < Test::Unit::TestCase
  def setup
	  # we repeat principle words to help weight them. 
	  # This test is rather delicate, since this system is mostly noise.
    @str1 = "This text deals with dogs. Dogs."
    @str2 = "This text involves dogs too. Dogs! "
    @str3 = "This text revolves around cats. Cats."
    @str4 = "This text also involves cats. Cats!"
    @str5 = "This text involves birds. Birds."
  end
	
  def test_basic_indexing
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }
    assert ! lsi.needs_rebuild?
	  
	 # note that the closest match to str1 is str2, even though it is not
	 # the closest text match.
    assert_equal [@str2, @str5, @str3], lsi.find_related(@str1, 3)
  end

  def test_not_auto_rebuild
    lsi = Classifier::LSI.new :auto_rebuild => false
    lsi.add_item @str1, "Dog"
    lsi.add_item @str2, "Dog"
    assert lsi.needs_rebuild?
    lsi.build_index
    assert ! lsi.needs_rebuild?
  end

  def test_basic_categorizing
    lsi = Classifier::LSI.new
    lsi.add_item @str2, "Dog"
    lsi.add_item @str3, "Cat"
    lsi.add_item @str4, "Cat"
    lsi.add_item @str5, "Bird"

    assert_equal "Dog", lsi.classify( @str1 )
    assert_equal "Cat", lsi.classify( @str3 )
    assert_equal "Bird", lsi.classify( @str5 )  
  end
	
  def test_external_classifying
    lsi = Classifier::LSI.new
    bayes = Classifier::Bayes.new 'Dog', 'Cat', 'Bird'
    lsi.add_item @str1, "Dog" ; bayes.train_dog @str1
    lsi.add_item @str2, "Dog" ; bayes.train_dog @str2
    lsi.add_item @str3, "Cat" ; bayes.train_cat @str3
    lsi.add_item @str4, "Cat" ; bayes.train_cat @str4
    lsi.add_item @str5, "Bird" ; bayes.train_bird @str5

    # We're talking about dogs. Even though the text matches the corpus on 
    # cats better.  Dogs have more semantic weight than cats. So bayes
    # will fail here, but the LSI recognizes content.
    tricky_case = "This text revolves around dogs."
    assert_equal "Dog", lsi.classify( tricky_case )
    assert_not_equal "Dog", bayes.classify( tricky_case )
  end 
	
  def test_recategorize_interface
    lsi = Classifier::LSI.new
    lsi.add_item @str1, "Dog"
    lsi.add_item @str2, "Dog"
    lsi.add_item @str3, "Cat"
    lsi.add_item @str4, "Cat"
    lsi.add_item @str5, "Bird"
    
    tricky_case = "This text revolves around dogs."
    assert_equal "Dog", lsi.classify( tricky_case )
    
    # Recategorize as needed.
    lsi.categories_for(@str1).clear.push "Cow"
    lsi.categories_for(@str2).clear.push "Cow"

    assert !lsi.needs_rebuild?
    assert_equal "Cow", lsi.classify( tricky_case )	  
  end
	
  def test_search
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    # Searching by content and text, note that @str2 comes up first, because
    # both "dog" and "involve" are present. But, the next match is @str1 instead
    # of @str4, because "dog" carries more weight than involves. 
    assert_equal( [@str2, @str1, @str4, @str5, @str3],
                  lsi.search("dog involves", 100) )
                  
    # Keyword search shows how the space is mapped out in relation to 
    # dog when magnitude is remove. Note the relations. We move from dog
    # through involve and then finally to other words. 
    assert_equal( [@str1, @str2, @str4, @str5, @str3],
                  lsi.search("dog", 5) )
  end
	
  def test_serialize_safe
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    lsi_md = Marshal.dump lsi
    lsi_m = Marshal.load lsi_md

    assert_equal lsi_m.search("cat", 3), lsi.search("cat", 3)
    assert_equal lsi_m.find_related(@str1, 3), lsi.find_related(@str1, 3)
  end
	
  def test_keyword_search
    lsi = Classifier::LSI.new
    lsi.add_item @str1, "Dog"
    lsi.add_item @str2, "Dog"
    lsi.add_item @str3, "Cat"
    lsi.add_item @str4, "Cat"
    lsi.add_item @str5, "Bird"

    assert_equal [:dog, :text, :deal], lsi.highest_ranked_stems(@str1)
  end
	
  def test_summary
    assert_equal "This text involves dogs too [...] This text also involves cats", [@str1, @str2, @str3, @str4, @str5].join.summary(2)
  end
end