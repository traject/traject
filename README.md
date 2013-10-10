# Traject

Tools for reading MARC records, transforming them with indexing rules, and indexing to Solr.
Might be used to index MARC data for a Solr-based discovery product like [Blacklight](https://github.com/projectblacklight/blacklight) or [VUFind](http://vufind.org/).

Traject might also be generalized to a set of tools for getting structured data from a source, and sending it to a destination. 


**Traject is nearing 1.0, it is robust, feature-rich and ready for trial use**

[![Gem Version](https://badge.fury.io/rb/traject.png)](http://badge.fury.io/rb/traject)
[![Build Status](https://travis-ci.org/traject-project/traject.png)](https://travis-ci.org/traject-project/traject)


## Background/Goals

Initially by Jonathan Rochkind (Johns Hopkins Libraries) and Bill Dueber (University of Michigan Libraries). 

Traject was born out of our experience with similar tools, including the very popular and useful [solrmarc](https://code.google.com/p/solrmarc/) by Bob Haschart; and Bill Dueber's own [marc2solr](http://github.com/billdueber/marc2solr/). 

We're comfortable programming (especially in a dynamic language), and want to be able to experiment with different indexing patterns quickly, easily, and testably; but are admittedly less comfortable in Java.  In order to have a tool with the API's and usage patterns convenient for us, we found we could do it better in JRuby -- Ruby on the JVM. 

* Basic configuration files can be easily written even by non-rubyists,  with a few simple directives traject provides. But config files are 'ruby all the way down', so we can provide a gradual slope to more complex needs, with the full power of ruby. 
* Easy to program, easy to read, easy to modify.  
* Fast. Traject by default indexes using multiple threads, on multiple cpu cores. 
* Composed of decoupled components, for flexibility and extensibility. The whole code base is only 6400 lines of code, more than a third of which is tests.
* Designed to support local code and configuration that's maintainable and testable, an can be shared between projects as ruby gems. 
* Designed with batch execution in mind: flexible logging, good exit codes, good use of stdin/stdout/stderr. 


## Installation

Traject runs under jruby (ruby on the JVM). I recommend [chruby](https://github.com/postmodern/chruby) and [ruby-install](https://github.com/postmodern/ruby-install#readme) for installing and managing ruby installations. (traject is tested
and supported for ruby 1.9 -- recent versions of jruby should run under 1.9 mode by default).

Then just `gem install traject`.

( **Note**: We may later provide an all-in-one .jar distribution, which does not require you to install jruby or use on your system. This is hypothetically possible. Is it a good idea?)


## Configuration files

traject is configured using configuration files. To get a sense of what they look like, you can
take a look at our sample non-trivial configuration file, 
[demo_config.rb](./test/test_support/demo_config.rb), which you'd run like 
`traject -c path/to/demo_config.rb marc_file.marc`.

Configuration files are actually just ruby -- so by convention they end in `.rb`.

We hope you can write basic useful configuration files without being a ruby expert,
traject gives you some easy functions to use for common diretives. But the full power
of ruby is available to you if needed. 

**rubyist tip**: Technically, config files are executed with `instance_eval` in a Traject::Indexer instance, so the special commands you see are just methods on Traject::Indexer (or mixed into it). But you can
call ordinary ruby `require` in config files, etc., too, to load
external functionality. See more at Extending Logic below.

You can keep your settings and indexing rules in one config file,
or split them accross multiple config files however you like. (Connection details vs indexing? Common things vs environmental specific things?)

There are two main categories of directives in your configuration files: _Settings_, and _Indexing Rules_.

## Settings

Settings are a flat list of key/value pairs, where the keys are always strings and the values usually are. They look like this
in a config file:

~~~ruby
# configuration_file.rb
# Note that "#" is a comment, cause it's just ruby

settings do
  # Where to find solr server to write to
  provide "solr.url", "http://example.org/solr"

  # If you are connecting to Solr 1.x, you need to set
  # for SolrJ compatibility:
  # provide "solrj_writer.parser_class_name", "XMLResponseParser"

  # solr.version doesn't currently do anything, but set it
  # anyway, in the future it will warn you if you have settings
  # that may not work with your version.
  provide "solr.version", "4.3.0"

  # default source type is binary, traject can't guess
  # you have to tell it.
  provide "marc_source.type", "xml"

  # various others...
  provide "solrj_writer.commit_on_close", "true"

  # By default, we use the Traject::Marc4JReader, which
  # can read marc8 and ISO8859_1 -- if your records are all in UTF8,
  # the pure-ruby MarcReader may be faster...
  # provide "reader_class_name", "Traject::MarcReader"
  # If you ARE using the Marc4JReader, it defaults to "BESTGUESS"
  # as to encoding when reading binary, you may want to tell it instead
  provide "marc4j_reader.source_encoding", "MARC8" # or UTF-8 or ISO8859_1
end
~~~

`provide` will only set the key if it was previously unset, so first
setting wins, and command-line comes first of all and overrides everything.
You can also use `store` if you want to force-set, last set wins.

See, docs page on [Settings](./doc/settings.md) for list
of all standardized settings.


## Indexing rules: Let's start with `to_field` and `extract_marc`

There are a few methods that can be used to create indexing rules, but the
one you'll most common is called `to_field`, and establishes a rule
to extract content to a particular named output field. 

The extraction rule can use built-in 'macros', or, as we'll see later, 
entirely custom logic. 

The built-in macro you'll use the most is `extract_marc`, to extract
data out of a MARC record according to a tag/subfield specification. 

~~~ruby
    # Take the value of the first 001 field, and put
    # it in output field 'id', to be indexed in Solr
    # field 'id'
    to_field "id", extract_marc("001", :first => true)

    # 245 subfields a, p, and s. 130, all subfields.
    # built-in punctuation trimming routine.
    to_field "title_t", extract_marc("245nps:130", :trim_punctuation => true)

    # Can limit to certain indicators with || chars.
    # "*" is a wildcard in indicator spec.  So
    # 856 with first indicator '0', subfield u.
    to_field "email_addresses", extract_marc("856|0*|u")

    # Can list tag twice with different field combinations
    # to extract separately
    to_field "isbn", extract_marc("245a:245abcde")

    # For MARC Control ('fixed') fields, you can optionally
    # use square brackets to take a byte offset. 
    to_field "langauge_code", extract_marc("008[35-37]")
~~~

`extract_marc` by default includes all 'alternate script' linked fields correspoinding
to matched specifications, but you can turn that off, or extract *only* corresponding
880s. 

    to_field "title", extract_marc("245abc", :alternate_script => false)
    to_field "title_vernacular", extract_marc("245abc", :alternate_script => :only)

By default, specifications with multiple subfields (like "240abc") will produce one single string of output for each matching field. Specifications with single subfields (like "020a") will split subfields and produce an output string for each matching subfield.    

For the syntax and complete possibilities of the specification
string argument to extract_marc, see docs at the [MarcExtractor class](./lib/traject/marc_extractor.rb) ([rdoc](http://rdoc.info/gems/traject/Traject/MarcExtractor)).

`extract_marc` also supports `translation maps` similar
to SolrMarc's. There are some translation maps provided by traject,
and you can also define your own, in yaml or ruby. Translation maps are especially useful
for mapping form MARC codes to user-displayable strings:

~~~ruby
    # "translation_map" will be passed to Traject::TranslationMap.new
    # and the created map used to translate all values
    to_field "language", extract_marc("008[35-37]:041a:041d", :translation_map => "marc_language_code")
~~~

To see all options for `extract_marc`, see the [method documentation](http://rdoc.info/gems/traject/Traject/Macros/Marc21:extract_marc)

## other built-in utility macros

Other built-in methods that can be used with `to_field` include a hard-coded
literal string:

    to_field "source", literal("LIB_CATALOG")

The current record serialized back out as MARC, in binary, XML, or json:

    # or :format => "json" for marc-in-json
    # or :format => "binary", by default Base64-encoded for Solr
    # 'binary' field, or, for more like what SolrMarc did, without
    # escaping:
    to_field "marc_record_raw", serialized_marc(:format => "binary", :binary_escape => false, :allow_oversized => true)

Text of all fields in a range:

    to_field "text", extract_all_marc_values(:from => 100, :to => 899)


All of these methods are defined at [Traject::Macros::Marc21](./lib/traject/macros/marc21.rb) ([rdoc](http://rdoc.info/gems/traject/Traject/Macros/Marc21))

## more complex canned MARC semantic logic

Some more complex (and opinionated/subjective) algorithms for deriving semantics
from Marc are also packaged with Traject, but not available by default. To make
them available to your indexing, you just need to use ruby `require` and `extend`. 

A number of methods are in [Traject::Macros::Marc21Semantics](./lib/traject/macros/marc21_semantics.rb) ([rdoc](http://rdoc.info/gems/traject/Traject/Macros/Marc21Semantics))

    require 'traject/macros/marc21_semantics'
    extend Traject::Macros::Marc21Semantics

    to_field 'title_sort',        marc_sortable_title
    to_field 'broad_subject',     marc_lcc_to_broad_category
    to_field "geographic_facet",  marc_geo_facet
    # And several more

And, there's a routine for classifying MARC to an internal
format/genre/type vocabulary:

    require 'traject/macros/marc_format_classifier'
    extend Traject::Macros::MarcFormats

    to_field 'format_facet',    marc_formats


## Custom logic

The built-in routines are there for your convenience, but if you need
something local or custom, you can write ruby logic directly
in a configuration file, using a ruby block, which looks like this:

    to_field "id" do |record, accumulator|
       # take the record's 001, prefix it with "bib_",
       # and then add it to the 'accumulator' argument,
       # to send it to the specified output field
       value = record['001']
       value = "bib_#{value}"
       accumulator << value
    end

`do |record, accumulator|` is the definition of a ruby block taking
two arguments.  The first one passed in will be a MARC record. The
second is an array, you add values to the array to send them to
output. 

Here's a more realistic example that shows how you'd get the
record type byte 06 out of a MARC leader, then translate it
to a human-readable string with a TranslationMap

    to_field "marc_type" do |record, accumulator|
      leader06 = record.leader.byteslice(6)
      # this translation map doesn't actually exist, but could
      accumulator << TranslationMap.new("marc_leader")[ leader06 ]
    end

You can also add a block onto the end of a built-in 'macro', to 
further customize the output. The `accumulator` passed to your block
will already have values in it from the first step, and you can
use ruby methods like `map!` to modify it:

    to_field "big_title", extract_marc("245abcdefg") do |record, accumulator|
      # put it all in all uppercase, I don't know why. 
      accumulator.map! {|v| v.upcase}
    end

There are many more things you can do with custom logic blocks like this too,
including additional features we haven't discussed yet. 

If you find yourself repeating boilerplate code in your custom logic, you can
even create your own 'macros' (like `extract_marc`). `extract_marc` and other
macros are nothing more than methods that return ruby lambda objects of
the same format as the blocks you write for custom logic. 

For tips, gotchas, and a more complete explanation of how this works, see
additional documentation page on [Indexing Rules: Macros and Custom Logic](./doc/indexing_rules.md)

## each_record and after_processing

In addition to `to_field`, an `each_record` method is available, which, 
like `to_field`, is executed for every record, but without being tied
to a specific field. 

`each_record` can be used for logging or notifiying; computing intermediate
results; or writing to more than one field at once. 

~~~ruby
  each_record do |record|
    some_custom_logging(record)
  end
~~~

For more on `each_record`, see documentation page on [Indexing Rules: Macros and Custom Logic](./doc/indexing_rules.md).

There is also an `after_processing` method that can be used to register
logic that will be called after the entire has been processed. You can use it for whatever custom
ruby code you might want for your app (send an email? Clean up a log file? Trigger
a Solr replication?)

~~~ruby
after_processing do 
  whatever_ruby_code
end
~~~


## Writers

Traject uses modular 'Writer' classes to take the output hashes from transformation, and
send them somewhere or do something useful with them. 

By default traject uses the [Traject::SolrJWriter](lib/traject/solrj_writer.rb) ([rdoc](http://rdoc.info/gems/traject/Traject/SolrJWriter)) to send to Solr for indexing. 
A couple other writers are available too, mostly for debugging purposes:
[Traject::DebugWriter](lib/traject/debug_writer.rb) ([rdoc](http://rdoc.info/gems/traject/Traject/DebugWriter)) 
and [Traject::JsonWriter](lib/traject/json_writer.rb) ([rdoc](http://rdoc.info/gems/traject/Traject/JsonWriter)) 

You set which writer is being used in settings (`provide "writer_class_name", "Traject::DebugWriter"`),
or on the command-line as a shortcut with `-w Traject::DebugWriter`.

You can write your own Readers and Writers if you'd like, see comments at top
of [Traject::Indexer](lib/traject/indexer.rb).

## The traject command Line

The simplest invocation is:

    traject -c conf_file.rb marc_file.mrc

Traject assumes marc files are in ISO 2709 binary format; it is not
currently able to guess marc format type from filenames. If you are reading
marc files in another format, you need to tell traject either with the `marc_source.type` or the command-line shortcut:

    traject -c conf.rb -t xml marc_file.xml

You can supply more than one conf file with repeated `-c` arguments.

    traject -c connection_conf.rb -c indexing_conf.rb marc_file.mrc

If you supply a `--stdin` argument, traject will try to read from stdin.
You can only supply one marc file at a time, but we can take advantage of stdin to get around this:

    cat some/dir/*.marc | traject -c conf_file.rb --stdin

You can set any setting on the command line with `-s key=value`.
This will over-ride any settings set with `provide` in conf files.

    traject -c conf_file.rb marc_file -s solr.url=http://somehere/solr -s solr.url=http://example.com/solr -s solrj_writer.commit_on_close=true

There are some built-in command-line option shortcuts for useful
settings:

Use `--debug-mode` to output in a human-readable format, instead of sending to solr.
Also turns on debug logging and restricts processing to single-threaded. Useful for
debugging or sanity checking.

    traject --debug-mode -c conf_file.rb marc_file

Use `-u` as a shortcut for `s solr.url=X`

    traject -c conf_file.rb -u http://example.com/solr marc_file.mrc
    
Run `traject -h` to see the command line help screen listing all available options. 

Also see `-I load_path` option and suggestions for Bundler use under Extending With Your Own Code.

See also [Hints for batch and cronjob use](./doc/batch_execution.md) of traject.


## Known extensions

### Readers/Writers
* [traject_alephsequential_reader](https://github.com/traject-project/traject_alephsequential_reader/): read MARC files serialized in the
AlephSequential format, as output by Ex Libris's Alpeh ILS.

* [traject_horizon](https://github.com/jrochkind/traject_horizon): Export MARC records directly from a Horizon ILS rdbms, as serialized MARC or to  index into Solr.


### Macros
* [traject_umich_format](https://github.com/billdueber/traject_umich_format/): opinionated code and associated macros to extract format
(book, audio file, etc.) and types (bibliography, conference report, etc.) from a MARC record. Code mirrors that used by the University
of Michigan, and is an alternate approach to that taken by the `marc_formats` macro in `Traject::Macros::MarcFormatClassifier`.



## Extending With Your Own Code

Traject config files are full live ruby files, where you can do anything,
including declaring new classes, etc.

However, beyond limited trivial logic, you'll want to organize your
code reasonably into separate files, not jam everything into config
files.

Traject wants to make sure it makes it convenient for you to do so,
whether project-specific logic in files local to the traject project,
or in ruby gems that can be shared between projects.

There are standard ruby mechanisms you can use to do this, and
traject provides a couple features to make sure this remains
convenient with the traject command line.

For more information, see documentation page on [Extending With Your
Own Code](./doc/extending.md)

**Expert summary** :
* Traject `-I` argument command line can be used to list directories to
  add to the load path, similar to the `ruby -I` argument. You
  can then 'require' local project files from the load path.
  * translation map files found on the load path or in a
    "./translation_maps" subdir on the load path will be found
    for Traject translation maps.
* Use [Bundler](http://bundler.io/) with traject simply by creating a Gemfile with `bundler init`,
  and then running command line with `bundle exec traject` or 
  even `BUNDLE_GEMFILE=path/to/Gemfile bundle exec traject`

## More

* [Other traject commands](./doc/other_commands.md) including `marcout`, and `commit`
* [Hints for batch and cronjob use](./doc/batch_execution.md) of  traject.


# Development

Run tests with `rake test` or just `rake`.  Tests are written using Minitest (please, no rspec).  We use the spec-style describe/it to
list the tests -- but generally prefer unit-style "assert_*" methods
to make actual assertions, for clarity.

Some tests need to run against a solr instance. Currently no solr
instance is baked in.  You can provide your own solr instance to test against and set shell ENV variable
"solr_url", and the tests will use it. Otherwise, tests will
use a mocked up Solr instance.

To make a pull request, please make a feature branch *created from the master branch*, not from an existing feature branch. (If you need to do a feature branch dependent on an existing not-yet merged feature branch... discuss
this with other developers first!)

Pull requests should come with tests, as well as docs where applicable. Docs can be inline rdoc-style, edits to this README,
and/or extra files in ./docs -- as appropriate for what needs to be docs.

**Inline api docs** Note that our [`.yardopts` file](./.yardopts) used by rdoc.info to generate
online api docs has a `--markup markdown` specified -- inline class/method docs are in markdown, not rdoc. 

## TODO


* Unicode normalization. Has to normalize to NFKC on way out to index. Except for serialized marc field and other exceptions? Except maybe don't have to, rely on solr analyzer to do it?

  * Should it normalize to NFC on the way in, to make sure translation maps and other string comparisons match properly?

  * Either way, all optional/configurable of course. based
    on Settings.

* CommandLine class isn't covered by tests -- it's written using functionality
from Indexer and other classes taht are well-covered, but the CommandLine itself
probably needs some tests -- especially covering error handling, which probably
needs a bit more attention and using exceptions instead of exits, etc.

* Optional built-in jetty stop/start to allow indexing to Solr that wasn't running before. maybe https://github.com/projecthydra/jettywrapper ?
