require 'traject'
require 'traject/qualified_const_get'

#
# Writes to a Solr using SolrJ, and the SolrJ HttpSolrServer.
#  (sub-class later for the ConcurrentUpdate server?)
#
# settings:
#   [solrj_writer.url] Your solr url (required)
#   [solrj_writer.solr_class_name]  Defaults to "HttpSolrServer". You can specify
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

  def initialize(argSettings)
    @settings = argSettings
    settings_check!(settings)

    ensure_solrj_loaded!

    solr_server # init
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
        jardir = settings["solrj.jar_dir"] || "/Users/jrochkind/code/solrj-gem/lib"
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
    solr_server.add(doc)
  end

  def close
    solr_server.commit if settings["solrj_writer.commit_on_close"].to_s == "true"

    solr_server.shutdown
    @solr_server = nil
  end


  def solr_server
    @solr_server ||= instantiate_solr_server!
  end
  attr_writer :solr_server # mainly for testing

  # Instantiates a solr server of class settings["solrj_writer.server_class_name"] or "HttpSolrServer"
  # and initializes it with settings["solrj_writer.url"]
  def instantiate_solr_server!
    server_class  = qualified_const_get( settings["solrj_writer.server_class_name"] || "HttpSolrServer" )
    server        = server_class.new( settings["solrj_writer.url"].to_s );

    if parser_name = settings["solrj_writer.parser_class_name"]
      parser = org.apache.solr.client.solrj.impl.const_get(parser_name).new
      server.setParser( parser )
    end

    server
  end

  def settings_check!(settings)
    unless settings.has_key?("solrj_writer.url") && ! settings["solrj_writer.url"].nil?
      raise ArgumentError.new("SolrJWriter requires a 'solrj_writer.url' solr url in settings")
    end
  end

end