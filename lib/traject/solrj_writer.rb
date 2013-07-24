require 'yell'

require 'traject'
require 'traject/qualified_const_get'

require 'uri'

#
# Writes to a Solr using SolrJ, and the SolrJ HttpSolrServer.
#  (sub-class later for the ConcurrentUpdate server?)
#
# settings:
#   [solr.url] Your solr url (required)
#   [solrj_writer.server_class_name]  Defaults to "HttpSolrServer". You can specify
#                                   another Solr Server sub-class, but it has
#                                   to take a one-arg url constructor. Maybe
#                                   subclass this writer class and overwrite
#                                   instantiate_solr_server! otherwise
#   [solrj.jar_dir] Custom directory containing all of the SolrJ jars. All
#                   jars in this dir will be loaded. Otherwise,
#                   we load our own packaged solrj jars. This setting
#                   can't really be used differently in the same app instance,
#                   since jars are loaded globally.
#   [solrj_writer.parser_class_name] A String name of a class in package
#                                    org.apache.solr.client.solrj.impl,
#                                    we'll instantiate one with a zero-arg
#                                    constructor, and pass it as an arg to setParser on
#                                    the SolrServer instance, if present.
#                                    NOTE: For contacting a Solr 1.x server, with the
#                                    recent version of SolrJ used by default, set to
#                                    "XMLResponseParser"
#   [solrj_writer.commit_on_close]  If true (or string 'true'), send a commit to solr
#                                   at end of #process.
class Traject::SolrJWriter
  include Traject::QualifiedConstGet

  attr_reader :settings
  attr_accessor :error_contexts

  def initialize(argSettings)
    @settings = argSettings
    settings_check!(settings)

    ensure_solrj_loaded!

    solr_server # init

    self.error_contexts = []
  end

  # Loads solrj if not already loaded. By loading all jars found
  # in settings["solrj.jar_dir"]
  def ensure_solrj_loaded!
    unless defined?(HttpSolrServer) && defined?(SolrInputDocument)
      require 'java'

      tries = 0
      begin
        tries += 1
        java_import org.apache.solr.client.solrj.impl.HttpSolrServer
        java_import org.apache.solr.common.SolrInputDocument
      rescue NameError  => e
        # /Users/jrochkind/code/solrj-gem/lib"

        included_jar_dir = File.expand_path("../../vendor/solrj/lib", File.dirname(__FILE__))

        jardir = settings["solrj.jar_dir"] || included_jar_dir
        Dir.glob("#{jardir}/*.jar") do |x|
          require x
        end
        if tries > 1
          raise LoadError.new("Can not find SolrJ java classes")
        else
          retry
        end
      end
    end

    # And for now, SILENCE SolrJ logging
    org.apache.log4j.Logger.getRootLogger().addAppender(org.apache.log4j.varia.NullAppender.new)
  end

  def put(hash)
    doc = SolrInputDocument.new

    hash.each_pair do |key, value_array|
      value_array.each do |value|
        doc.addField( key, value )
      end
    end

    # TODO: Buffer docs internally, add in arrays, one http
    # transaction per array. Is what solrj wiki recommends.

    begin
      solr_server.add(doc)
    rescue org.apache.solr.common.SolrException, org.apache.solr.client.solrj.SolrServerException  => e
      # Honestly not sure what the difference is between those types, but SolrJ raises both
      log_exception(e)

      if fatal_exception? e
        logger.fatal ("SolrJ exception judged fatal, raising...")
        raise e
      end
    end
  end

  def logger
    settings["logger"] ||= Yell.new(STDERR, :level => "gt.fatal") # null logger
  end

  # If an exception is encountered talking to Solr, is it one we should
  # entirely give up on? SolrJ doesn't use a useful exception class hieararchy,
  # we have to look into it's details and guess.
  def fatal_exception?(e)


    root_cause = e.respond_to?(:getRootCause) && e.getRootCause

    # Various kinds of inability to actually talk to the
    # server look like this:
    if root_cause.kind_of? java.io.IOException
      return true
    end

    return false
  end

  def log_exception(e)
    indent = "    "

    msg = "Could not index record\n"
    msg += indent + "Exception: " + e.class.name + ": " + e.message + "\n"
    msg += indent + e.backtrace.first + "\n"

    if (e.respond_to?(:getRootCause) && e.getRootCause && e != e.getRootCause )
      caused_by = e.getRootCause
      msg += indent + "Caused by\n"
      msg += indent + caused_by.class.name + ": " + caused_by.message + "\n"
      msg += indent + caused_by.backtrace.first + "\n"
    end

    logger.error(msg)

  end

  def close
    if settings["solrj_writer.commit_on_close"].to_s == "true"
      logger.info "SolrJWriter: Sending commit to solr..."
      solr_server.commit 
    end

    solr_server.shutdown
    @solr_server = nil
  end


  def solr_server
    @solr_server ||= instantiate_solr_server!
  end
  attr_writer :solr_server # mainly for testing

  # Instantiates a solr server of class settings["solrj_writer.server_class_name"] or "HttpSolrServer"
  # and initializes it with settings["solr.url"]
  def instantiate_solr_server!
    server_class  = qualified_const_get( settings["solrj_writer.server_class_name"] || "HttpSolrServer" )
    server        = server_class.new( settings["solr.url"].to_s );

    if parser_name = settings["solrj_writer.parser_class_name"]
      #parser = org.apache.solr.client.solrj.impl.const_get(parser_name).new
      parser = Java::JavaClass.for_name("org.apache.solr.client.solrj.impl.#{parser_name}").ruby_class.new
      server.setParser( parser )
    end

    server
  end

  def settings_check!(settings)
    unless settings.has_key?("solr.url") && ! settings["solr.url"].nil?
      raise ArgumentError.new("SolrJWriter requires a 'solr.url' solr url in settings")
    end

    unless settings["solr.url"] =~ /^#{URI::regexp}$/
      raise ArgumentError.new("SolrJWriter requires a 'solr.url' setting that looks like a URL, not: `#{settings['solr.url']}`")
    end
  end

end