# Traject settings

Traject settings are a flat list of key/value pairs -- a single
Hash, not nested. Keys are always strings, and dots (".") can be
used for grouping and namespacing.

Values are usually strings, but occasionally something else.

Settings can be set in configuration files, or on the command
line.

## Known settings

* json_writer.pretty_print: used by the JsonWriter, if set to true, will output pretty printed json (with added whitespace) for easier human readability. Default false. 

* marc_source.type: default 'binary'. Can also set to 'xml' or (not yet implemented todo) 'json'. Command line shortcut `-t`

* reader_class_name: a Traject Reader class, used by the indexer as a source of records. Default Traject::MarcReader. See Traject::Indexer for more info. Command-line shortcut `-r`

* solr.url: URL to connect to a solr instance for indexing, eg http://example.org:8983/solr . Command-line short-cut `-u`. 

* solrj.jar_dir: SolrJWriter needs to load Java .jar files with SolrJ. It will load from a packaged SolrJ, but you can load your own SolrJ (different version etc) by specifying a directory. All *.jar in directory will be loaded.

* solr.version: Set to eg "1.4.0", "4.3.0"; currently un-used, but in the future will control
  change some default settings, and/or sanity check and warn you if you're doing something
  that might not work with that version of solr. Set now for help in the future. 

* solrj_writer.commit_on_close: default false, set to true to have SolrJWriter send an explicit commit message to Solr after indexing.

* solrj_writer.parser_class_name: Set to "XMLResponseParser" or "BinaryResponseParser". Will be instantiated and passed to the solrj.SolrServer with setResponseParser. Default nil, use SolrServer default. To talk to a solr 1.x, you will want to set to "XMLResponseParser"

* solrj_writer.server_class_name: String name of a solrj.SolrServer subclass to be used by SolrJWriter. Default "HttpSolrServer"

* writer_class_name: a Traject Writer class, used by indexer to send processed dictionaries off. Default Traject::SolrJWriter, also available Traject::JsonWriter. See Traject::Indexer for more info. Command line shortcut `-w`