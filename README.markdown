[![Build Status](https://travis-ci.org/Ch4s3/classifier.svg)](https://travis-ci.org/Ch4s3/classifier)

## Welcome to Classifier

Classifier is a general module to allow Bayesian and other types of classifications.

## Download

* https://github.com/cardmagic/classifier
* gem install classifier
* git clone https://github.com/cardmagic/classifier.git

## Dependencies

If you install Classifier from source, you'll need to install Roman Shterenzon's fast-stemmer gem with RubyGems as follows:

    gem install fast-stemmer

Currently using Classifier with JRuby requires the all ruby version of fast-stemmer, [Stemmify](https://github.com/raypereda/stemmify).
Future versions will rely on a java implementation.

    gem install stemmify

If you would like to speed up LSI classification by at least 10x, please install the following libraries:
GNU GSL:: http://www.gnu.org/software/gsl
rb-gsl:: http://rb-gsl.rubyforge.org

Notice that LSI will work without these libraries, but as soon as they are installed, Classifier will make use of them. No configuration changes are needed, we like to keep things ridiculously easy for you.

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
  
Please see the Classifier::LSI documentation for more information. It is possible to index, search and classify
with more than just simple strings. 

### Latent Semantic Indexing

* http://www.c2.com/cgi/wiki?LatentSemanticIndexing
* http://www.chadfowler.com/index.cgi/Computing/LatentSemanticIndexing.rdoc
* http://en.wikipedia.org/wiki/Latent_semantic_analysis

## Authors    

* Lucas Carlson  (lucas@rufy.com)
* David Fayram II (dfayram@gmail.com)
* Cameron McBride (cameron.mcbride@gmail.com)
* Ivan Acosta-Rubio (ivan@softwarecriollo.com)

This library is released under the terms of the GNU LGPL. See LICENSE for more details.

