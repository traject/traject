# Traject

Tools for indexing MARC records to Solr.

Generalizable to tools for configuring mapping records to associative array data structures, and sending
them somewhere.

*Currently under development, not production ready*

## Background/Goals

## Installation

Traject runs under jruby (ruby on the JVM). I recommend [chruby](https://github.com/postmodern/chruby) and [ruby-install](https://github.com/postmodern/ruby-install#readme) for installing and managing ruby installations.

Then just `gem install traject`.

(*Note*: We may later provide an all-in-one .jar distribution, which does not require you to install jruby or use on your system. This is hypothetically possible. Is it a good idea?)

# Usage

## Configuration file format

The traject command-line utility requires you to supply it with a configuration file. So let's start by describing the configuration file.

Configuration files are actually just ruby -- so by convention they end in `.rb`.

Don't worry, you don't neccesarily need to know ruby well to write them, they give you a subset of ruby to work with. But the full power
of ruby is available to you.

*rubyist tip*: Technically, config files are `instance_eval`d in a Traject::Indexer instance, so the special commands you see are just methods on Traject::Indexer (or mixed into it). But you can
call ordinary ruby `require` in config files, etc., too, to load
external functionality. See more at Extending Logic below.

There are two main categories of things in your configuration files: Settings, and Indexing Rules.

### Settings

Settings are a flat list of key/value pairs, where the keys are always strings and the values usually are. They look like this
in a config file:

~~~ruby
# configuration_file.rb
# Note that "#" is a comment, cause it's just ruby

settings do
  # Where to find solr server to write to
  store "solr.url", "http://example.org/solr"

  # solr.version doesn't currently do anything, but set it
  # anyway, in the future it will warn you if you have settings
  # that may not work with your version.
  store "solr.version", "4.3.0"

  # default source type is binary, traject can't guess
  # you have to tell it.
  store "marc_source.type", "xml"

  # settings can be set on command line instead of
  # config file too.

  # There are more things you can set, see, docs page
  # on [Settings][./doc/settings.md], eg:
  store "solrj_writer.commit_on_close", "true"
end
~~~

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
to_field("source"), literal("LIB_CATALOG")

# Serialize the marc record back out and
# put it in a solr field.
to_field("marc_record"), serialized_marc(:format => "xml")
# or :format => "json" for marc-in-json
# or :format => "binary", by default Base64-encoded for Solr
# 'binary' field, or, for more like what SolrMarc did, without
# escaping:
to_field("marc_record_raw"), serialized_marc(:format => "binary", :binary_escape => false)

# Take ALL of the text from the marc record, useful for
# a catch-all field. Actually by default only takes
# from tags 100 to 899.
to_field("text"), extract_all_marc_values

# Now we have a simple example of the general utility function
# `extract_marc`
to_field("id"), extract_marc("001", :first => true)
~~~

`extract_marc` takes a marc tag/subfield specification, and optional
arguments. `:first => true` means if the specification returned multiple values, ignore all bet the first. It is wise to use this
*whenever you have a non-multi-valued solr field* even if you think "There should only be one 001 field anyway!", to deal with unexpected
data properly.

Other examples of the specification string, which can include multiple tag mentions, as well as subfields and indicators:

    # 245 subfields a, p, and s. 130, all subfields.
    # built-in punctuation trimming routine. 
    to_field("title_t"), extract_marc("245nps:130", :trim_punctuation => true)

    # Can limit to certain indicators with || chars.
    # "*" is a wildcard in indicator spec.  So
    # 856 with first indicator '0', subfield u.
    to_field("email_addresses"), extract_marc("856|0*|u")

The `extract_marc` function *by default* includes any linked
MARC `880` fields with alternate-script versions. Another reason
to use the `:first` option if you really only want one.



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
This will over-ride any settings from conf files. (TODO, I don't
think over-riding works, it's actually a bit tricky)

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


# Development

## TODO

* Logging
  * it's doing no logging of it's own
  * It's not properly setting up the solrj logging
  * Making solrj and it's own logging go to same place, accross jruby bridge, not sure
    (I want all of this code BUT the Solr writing stuff to be usable under MRI too,
     I want to repurpose the mapping code for DISPLAY too)

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

* Unicode normalization. Has to normalize to NFKC on way out to index. Except for serialized marc field and other exceptions? Except maybe don't have to, rely on solr analyzer to do it?

  * Should it normalize to NFC on the way in, to make sure translation maps and other string comparisons match properly?

  * Either way, all optional/configurable of course. based
    on Settings.

* More macros. Not all the built-in functionality that comes with SolrMarc is here yet. It can be provided as macros, either built in, or distro'd in other gems. If really needed  as macros, and not just something local configs build themselves as needed out of the parts already here.

* Command line code. It's only 150 lines, but it's kind of messy
jammed into one file *and lacks tests*. I couldn't figure out
what to do with it or how to test it. Needs a bit of love.
