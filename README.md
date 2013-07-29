# Traject

Tools for indexing MARC records to Solr.

Generalizable to tools for configuring mapping records to associative array data structures, and sending
them somewhere.

**Currently under development, not production ready**

## Background/Goals

I've used previous MARC indexing solutions, and borrowed a lot from their success, including the
venerable SolrMarc, which we greatly appreciate and from which we've learned a lot. But I realized
in order to get the solution with the internal architecture, features, and interface I wanted, I
could do it best in jruby (ruby on the JVM).

Traject aims to:

* Be simple and straightforward for simple use cases, hopefully being accessible even to non-rubyists, although it's in ruby
* Be composed of modular and re-composible elements, to provide flexibility for non-common use cases. You should be able to
do your own thing wherever you want, without having to give up
the already implemented parts you still do want, mixing and matching at will.
* Easily support re-use and sharing of mapping rules, within an installation and between organizations.
* Have a parsimonious or 'elegant' internal architecture, only a few architectural concepts to understand that everything else is built on, to hopefully make the internals easy to work with and maintain.
* Be high performance, including using multi-threaded concurrency where appropriate to maximize indexing throughput.


## Installation

Traject runs under jruby (ruby on the JVM). I recommend [chruby](https://github.com/postmodern/chruby) and [ruby-install](https://github.com/postmodern/ruby-install#readme) for installing and managing ruby installations.

Then just `gem install traject`.

( **Note**: We may later provide an all-in-one .jar distribution, which does not require you to install jruby or use on your system. This is hypothetically possible. Is it a good idea?)

# Usage

## Configuration file format

The traject command-line utility requires you to supply it with a configuration file. So let's start by describing the configuration file.

Configuration files are actually just ruby -- so by convention they end in `.rb`.

Don't worry, you don't neccesarily need to know ruby well to write them, they give you a subset of ruby to work with. But the full power
of ruby is available to you.

**rubyist tip**: Technically, config files are executed with `instance_eval` in a Traject::Indexer instance, so the special commands you see are just methods on Traject::Indexer (or mixed into it). But you can
call ordinary ruby `require` in config files, etc., too, to load
external functionality. See more at Extending Logic below.

There are two main categories of directives in your configuration files: _Settings_, and _Indexing Rules_.

### Settings

Settings are a flat list of key/value pairs, where the keys are always strings and the values usually are. They look like this
in a config file:

~~~ruby
# configuration_file.rb
# Note that "#" is a comment, cause it's just ruby

settings do
  # Where to find solr server to write to
  provide "solr.url", "http://example.org/solr"

  # solr.version doesn't currently do anything, but set it
  # anyway, in the future it will warn you if you have settings
  # that may not work with your version.
  provide "solr.version", "4.3.0"

  # default source type is binary, traject can't guess
  # you have to tell it.
  provide "marc_source.type", "xml"

  # settings can be set on command line instead of
  # config file too.

  # various others...
  provide "solrj_writer.commit_on_close", "true"
end
~~~

`provide` will only set the key if it was previously unset, so first
setting wins, and command-line comes first of all and overrides everything.
You can also use `store` if you want to force-set, last set wins.

See, docs page on [Settings][./doc/settings.md] for list
of all standardized settings.

### Indexing Rules

You can keep your settings and indexing rules in one config file,
or split them accross multiple config files however you like. (Connection details vs indexing? Common things vs environmental specific things?)

The main tool for indexing rules is the `to_field` command.
Which can be used with a few standard functions.

~~~ruby
# configuration.rb

# The first arguent, 'source' in this case, is what Solr field we're
# sending to. And the 'literal' function supplies a hard-coded
# constant string literal.
to_field "source", literal("LIB_CATALOG")

# you can call 'to_field' multiple times, additional values
# are concatenated
to_field "source", literal("ANOTHER ONE")

# Serialize the marc record back out and
# put it in a solr field.
to_field "marc_record", serialized_marc(:format => "xml")

# or :format => "json" for marc-in-json
# or :format => "binary", by default Base64-encoded for Solr
# 'binary' field, or, for more like what SolrMarc did, without
# escaping:
to_field "marc_record_raw", serialized_marc(:format => "binary", :binary_escape => false)

# Take ALL of the text from the marc record, useful for
# a catch-all field. Actually by default only takes
# from tags 100 to 899.
to_field "text", extract_all_marc_values

# Now we have a simple example of the general utility function
# `extract_marc`
to_field "id", extract_marc("001", :first => true)
~~~

`extract_marc` takes a marc tag/subfield specification, and optional
arguments. `:first => true` means if the specification returned multiple values, ignore all bet the first. It is wise to use this
*whenever you have a non-multi-valued solr field* even if you think "There should only be one 001 field anyway!", to deal with unexpected
data properly.

Other examples of the specification string, which can include multiple tag mentions, as well as subfields and indicators:

~~~ruby
  # 245 subfields a, p, and s. 130, all subfields.
  # built-in punctuation trimming routine.
  to_field "title_t", extract_marc("245nps:130", :trim_punctuation => true)

  # Can limit to certain indicators with || chars.
  # "*" is a wildcard in indicator spec.  So
  # 856 with first indicator '0', subfield u.
  to_field "email_addresses", extract_marc("856|0*|u")
~~~

The `extract_marc` function *by default* includes any linked
MARC `880` fields with alternate-script versions. Another reason
to use the `:first` option if you really only want one.

For MARC control (aka 'fixed') fields, you can use square
brackets to take a slice by byte offset.

    to_field "langauge_code", extract_marc("008[35-37]")

`extract_marc` also supports `translation maps` similar
to SolrMarc's. There will be some translation maps built in,
and you can provide your own. translation maps can be supplied
in yaml or ruby.  Translation maps are especially useful
for mapping form MARC codes to user-displayable strings. See Traject::TranslationMap for more info:

    # "translation_map" will be passed to Traject::TranslationMap.new
    # and the created map used to translate all values
    to_field "language", extract_marc("008[35-37]:041a:041d", :translation_map => "marc_language_code")

#### Direct indexing logic vs. Macros

It turns out all those functions we saw above used with `to_field` -- `literal`, `serialized_marc`, `extract_all_marc_values, and `extract_marc` -- are what Traject calls 'macros'.

They are all actually built based upon a more basic element of
indexing functionality, which you can always drop down to, and
which is used to build the macros. The basic use of `to_field`,
with directly specified logic instead of using a macro, looks like this:

~~~ruby
to_field "source" do |record, accumulator, context|
   accumulator << "LIB CATALOG"
end
~~~~

That's actually equivalent to the macro we used earlier: `to_field("source"), literal("LIB_CATALOG")`.

This direct use of to_field happens to be a ruby "block", which is
used to define a block of logic that can be stored and executed later. When the block is called, first argument (`record` above) is the marc_record being indexed (a ruby-marc MARC::Record object), and the second argument (`accumulator`) is a ruby array used to accumulate output values.

The third argument is a `Traject::Indexer::Context` object that can
be used for more advanced functionality, including caching expensive
per-record calculations, writing out to more than one output field at a time, or taking account of current Traject Settings in your logic. The third argument is optional, you can supply
a two-argument block too.

You can always drop out to this basic direct use whenever you need
special purpose logic, directly in the config file, writing in
ruby:

~~~ruby
# this is more or less nonsense, just an example
to_field "weird_title" do |record, accumlator, context|
   field = record['245']
   title = field['a']
   title.upcase! if field.indicator1 = '1'
   accumulator << title
end

# To make use of marc extraction by specification, just like
# marc_extract does, you may want to use the Traject::MarcExtractor
# class
to_field "weirdo" do |record, accumulator, context|
   list = MarcExtractor.new(record, "700a").extract
   # combine all the 700a's in ONE string, cause we're weird
   list = list.join(" ")
   accumulator << list
end
~~~~

You can also *combine* a macro and a direct block for some
post-processing. In this case, the `accumulator` parameter
in our block will start out with the values left by
the `extract_marc`:

~~~ruby
to_field "subjects", extract_marc("600:650:610") do |record, accumulator, context|
  # for some reason we want to uppercase all our subjects
  accumulator.collect! {|s| s.upcase }
end
~~~

If you find yourself repeating code a lot in direct blocks, you
can supply your _own_ macros, for local use, or even to share
with others in a ruby gem. See docs [Macros](./doc/macros.md)

There is also a method `each_record`, which is like `to_field`, but without
a specific field. It can be used for other side-effects of your choice, or
even for writing to multiple fields.

~~~ruby
  each_record do |record, context|
    # example of writing to two fields at once.
    (x, y) = Something.do_stuff
    (context["one_field"] ||= [])     << x
    (context["another_field"] ||= []) << y
  end
~~~

You could write or use macros for `each_record` too. It's suggested that
such a macro take the field names it will effect as arguments (example?)

`each_record` and `to_field` calls will be processed in one big order, guaranteed
in order.

~~~ruby
  to_field("foo") {...}  # will be called first on each record
  each_record {...}      # will always be called AFTER above has potentially added values
  to_field("foo") {...}  # and will be called after each of the preceding for each record
~~~

## Command Line

The simplest invocation is:

    traject -c conf_file.rb marc_file.mrc

Traject assumes marc files are in ISO 2709 binary format; it is not
currently able to buess marc format type. If you are reading
marc files in another format, you need to tell traject either with the `marc_source.type` or the command-line shortcut:

    traject -c conf.rb -t xml marc_file.xml

You can supply more than one conf file with repeated `-c` arguments.

    traject -c connection_conf.rb -c indexing_conf.rb marc_file.mrc

If you leave off the marc_file, traject will try to read from stdin. You can only supply one marc file at a time, but we can take advantage of stdin to get around this:

    cat some/dir/*.marc | traject -c conf_file.rb

You can set any setting on the command line with `-s key=value`.
This will over-ride any settings set with `provide` in conf files.

    traject -c conf_file.rb marc_file -s solr.url=http://somehere/solr -s solr.url=http://example.com/solr -s solrj_writer.commit_on_close=true

There are some built-in command-line option shortcuts for useful
settings:

Use `-j` to output as pretty-printed JSON
hashes, instead of sending to solr. Useful for debugging or sanity
checking.

    traject -j -c conf_file.rb marc_file

Use `-u` as a shortcut for `s solr.url=X`

    traject -c conf_file.rb -u http://example.com/solr marc_file.mrc

Also see `-I load_path` and `-g Gemfile` options under Extending Logic

## Extending Logic

TODO fill out nicer.

Basically:

command line `-I` can be used to append to the ruby $LOAD_PATH, and then you can simply `require` your local files, and then use them for
whatever. Macros, utility functions, translation maps, whatever.

If you want to use logic from other gems in your configuration mapping, you can do that too. This works for traject-specific
functionality like translation maps and macros, or for anything else.
To use gems, you can _either_ use straight rubygems, simply by
installing gems in your system and using `require` or `gem` commands... **or** you can use Bundler for dependency locking and other dependency management. To have traject use Bundler, create a `Gemfile` and then call traject command line with the `-g` option. With the `-g` option alone, Bundler will look in the CWD and parents for the first `Gemfile` it finds. Or supply `-g ./somewhere/MyGemfile` to anywhere.


# Development

Run tests with `rake test` or just `rake`.  Tests are written using Minitest (please, no rspec).  We use the spec-style describe/it to
list the tests -- but generally prefer unit-style "assert_*" methods
to make actual assertions, for clarity.

Some tests need to run against a solr instance. Currently no solr
instance is baked in.  You can provide your own solr instance to test against and set shell ENV variable
"solr_url", and the tests will use it. Otherwise, tests will
use a mocked up Solr instance.

Pull requests should come with tests, as well as docs where applicable. Docs can be inline rdoc-style, edits to this README,
and/or extra files in ./docs -- as appropriate for what needs to be docs.

## TODO

* Logging
  * Logging is currently... okay, not great.
  * Currently silencing SolrJ's own logging (by silencing log4j root logger) Think
    that may actually be okay -- we still log any exceptions solrj throws.
    * Cause, making solrj and it's own logging go to same place, accross jruby bridge, not sure
    (I want all of this code BUT the Solr writing stuff to be usable under MRI too,
     I want to repurpose the mapping code for DISPLAY too)
  * Do need to get SolrJWriter error logging to log recordID and position number
    of skipped record. A pain cause of current seperation of concerns architecture.

* Error handling. Related to logging. Catch errors indexing
  particular records, make
  sure they are logged in an obvious place, make sure processing proceeds with other
  records (if it should!) etc.

* Distro and the SolrJ jars. Right now the SolrJ jars are included in the gem (although they
  aren't actually loaded until you try to use the SolrJWriter). This is not neccesarily
  best. other possibilities:
  * Put them in their own gem
  * Make the end-user download them theirselves, possibly providing the ivy.xml's to do so for
    them.
  * Oh, this applies to Marc4J jars used by the Marc4JReader too.

* Various performance improvements, this is not optimized yet. Some improvements
  may challenge architecture, when they involve threading.
  * Profile and optimize marc loading -- right now just using ruby-marc, always.
  * Profile/optimize marc serialization back to stored filed, right now it uses
    known-to-be-slow rexml as part of ruby-marc.
  * Use threads for the mapping step? With celluloid, or threach, or other? Does
    this require thinking more about thread safety of existing code?
  * Use threads for writing to solr?
    * I am not sure about using the solrj ConcurrentUpdateSolrServer -- among other
      things, it seems to swallow solr errors, that i'm not sure we want to do.
    * But we can batch docs ourselves before HttpServer#add'ing them -- every
      solrj HTTPServer#add is an http transaction, but you can give it an ARRAY
      to load multiple at once -- and still get the errors, I think. (Have to test)
      Could be perf nearly as good as concurrentupdate? Or do that, but then make each
      HttpServer#add in one of our own manual threads (Celluloid? Or raw?), so
      continued processing doesn't block?

* Reading Marc8. It can't do it yet. Easiest way would be using Marc4j to read, or using it as a transcoder anyway. Don't really want to write marc8 transcoder in ruby.

* We need something like `to_field`, but without actually being
for mapping to a specific output field. For generic pre or post-processing, or multi-output-field logic. `before_record do &block`, `after_record do &block` , `on_each_record do &block`, one or more of those.

* Unicode normalization. Has to normalize to NFKC on way out to index. Except for serialized marc field and other exceptions? Except maybe don't have to, rely on solr analyzer to do it?

  * Should it normalize to NFC on the way in, to make sure translation maps and other string comparisons match properly?

  * Either way, all optional/configurable of course. based
    on Settings.

* More macros. Not all the built-in functionality that comes with SolrMarc is here yet. It can be provided as macros, either built in, or distro'd in other gems. If really needed  as macros, and not just something local configs build themselves as needed out of the parts already here.

* Command line code. It's only 150 lines, but it's kind of messy
jammed into one file *and lacks tests*. I couldn't figure out
what to do with it or how to test it. Needs a bit of love.

* Optional built-in jetty stop/start to allow indexing to Solr that wasn't running before. maybe https://github.com/projecthydra/jettywrapper ?
