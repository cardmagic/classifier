## Welcome to Classifier

Classifier is a general module to allow Bayesian and other types of classifications.

## Download

* https://github.com/cardmagic/classifier
* gem install classifier
* git clone https://github.com/cardmagic/classifier.git

## Dependencies

The `fast-stemmer` gem is required:

    gem install fast-stemmer

### Optional: GSL for Faster LSI

For faster LSI classification, install the GNU Scientific Library and its Ruby bindings.

#### Ruby 3.4+

The released `gsl` gem doesn't support Ruby 3.4+. Install from source with the compatibility fix:

    # Install GSL library
    brew install gsl        # macOS
    apt-get install libgsl-dev  # Ubuntu/Debian

    # Build and install the gem from the compatibility branch
    git clone https://github.com/cardmagic/rb-gsl.git
    cd rb-gsl
    git checkout fix/ruby-3.4-compatibility
    gem build gsl.gemspec
    gem install gsl-*.gem

#### Ruby 3.3 and earlier

    # macOS
    brew install gsl
    gem install gsl

    # Ubuntu/Debian
    apt-get install libgsl-dev
    gem install gsl

LSI works without GSL using a pure Ruby implementation. When GSL is installed, Classifier automatically uses it with no configuration needed.

To suppress the GSL notice when not using it:

    SUPPRESS_GSL_WARNING=true ruby your_script.rb

## Bayes

A Bayesian classifier by Lucas Carlson. Bayesian Classifiers are accurate, fast, and have modest memory requirements.

### Usage

    require 'classifier'
    b = Classifier::Bayes.new 'Interesting', 'Uninteresting'
    b.train_interesting "here are some good words. I hope you love them"
    b.train_uninteresting "here are some bad words, I hate you"
    b.classify "I hate bad words and you" # returns 'Uninteresting'

    require 'madeleine'
    m = SnapshotMadeleine.new("bayes_data") {
        Classifier::Bayes.new 'Interesting', 'Uninteresting'
    }
    m.system.train_interesting "here are some good words. I hope you love them"
    m.system.train_uninteresting "here are some bad words, I hate you"
    m.take_snapshot
    m.system.classify "I love you" # returns 'Interesting'

Using Madeleine, your application can persist the learned data over time.

### Bayesian Classification

* http://www.process.com/precisemail/bayesian_filtering.htm
* http://en.wikipedia.org/wiki/Bayesian_filtering
* http://www.paulgraham.com/spam.html

## LSI

A Latent Semantic Indexer by David Fayram. Latent Semantic Indexing engines
are not as fast or as small as Bayesian classifiers, but are more flexible, providing
fast search and clustering detection as well as semantic analysis of the text that
theoretically simulates human learning.

### Usage

    require 'classifier'
    lsi = Classifier::LSI.new
    strings = [ ["This text deals with dogs. Dogs.", :dog],
              ["This text involves dogs too. Dogs! ", :dog],
              ["This text revolves around cats. Cats.", :cat],
              ["This text also involves cats. Cats!", :cat],
              ["This text involves birds. Birds.",:bird ]]
    strings.each {|x| lsi.add_item x.first, x.last}

    lsi.search("dog", 3)
    # returns => ["This text deals with dogs. Dogs.", "This text involves dogs too. Dogs! ",
    #             "This text also involves cats. Cats!"]

    lsi.find_related(strings[2], 2)
    # returns => ["This text revolves around cats. Cats.", "This text also involves cats. Cats!"]

    lsi.classify "This text is also about dogs!"
    # returns => :dog

    lsi.classify_with_confidence "This text is also about dogs!"
    # returns => [:dog, 1.0]

Please see the Classifier::LSI documentation for more information. It is possible to index, search and classify
with more than just simple strings.

### Latent Semantic Indexing

* http://www.c2.com/cgi/wiki?LatentSemanticIndexing
* http://www.chadfowler.com/index.cgi/Computing/LatentSemanticIndexing.rdoc
* http://en.wikipedia.org/wiki/Latent_semantic_analysis

## Benchmarks

Run benchmarks to compare LSI performance:

    rake benchmark              # Run with current configuration
    rake benchmark:compare      # Compare GSL vs native Ruby

### GSL vs Native Ruby Comparison

| Documents | build_index | Overall Speedup |
|-----------|-------------|-----------------|
| 5         | 4x          | 2.5x            |
| 10        | 24x         | 5.5x            |
| 15        | 116x        | 17x             |

Sample comparison (15 documents):

    Operation              Native          GSL      Speedup
    ----------------------------------------------------------
    build_index            0.1412       0.0012       116.2x
    classify               0.0142       0.0049         2.9x
    search                 0.0102       0.0026         3.9x
    find_related           0.0069       0.0016         4.2x
    ----------------------------------------------------------
    TOTAL                  0.1725       0.0104        16.6x

The `build_index` operation (SVD computation) dominates total time and benefits most from GSL. Install GSL for production use with larger document sets.

## Authors

* Lucas Carlson  (lucas@rufy.com)
* David Fayram II (dfayram@gmail.com)
* Cameron McBride (cameron.mcbride@gmail.com)
* Ivan Acosta-Rubio (ivan@softwarecriollo.com)

This library is released under the terms of the GNU LGPL. See LICENSE for more details.

