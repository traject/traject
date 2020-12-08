# Traject settings

Traject settings are a flat list of key/value pairs -- a single
Hash, not nested. Keys are always strings, and dots (".") can be
used for grouping and namespacing.

Values are usually strings, but occasionally something else. String values can be easily
set via the command line.

Settings can be set in configuration files, usually like:

~~~ruby
settings do
  provide "key", "value"
end
~~~~

or on the command line: `-s key=value`.  There are also some command line shortcuts
for commonly used settings, see `traject -h`.

`provide` will only set the key if it was previously unset, so first time to set 'wins'. And command-line
settings are applied first of all. It's recommended you use `provide`.

`store` is also available, and forces setting of the new value overriding any previous value set.

## Known settings


### Reading (general)

* `reader_class_name`: a Traject Reader class, used by the indexer as a source of records.   Defaults is reader-specific: Traject::MarcReader (using the ruby marc gem) or Traject::NokogiriReader.Command-line shortcut `-r`

### Error handling

* `mapping_rescue`: Takes a proc/lambda/callable which accepts two arguments: A Traject::Context, and an exception.  Called if an unexpected error is raised when executing indexing rules. The default when this is unset, is to log and re-raise, which will halt execution. It usually means a bug in your mapping code, that you will want to know about.  See default logic at Traject::Indexer#default_mapping_rescue

  You may instead want to skip the record and continue with indexing, or even conditionally
  decide which to do. In a custom handler, if you want to halt execution, you should re-raise the
  exception (or raise another). If you want to skip the record and continue, call `context.skip!`
  and do not raise.

  The "stabby lambda" syntax is useful for providing a lambda object with proper parsing
  precedence to not need parentheses.

      error_count = Concurrent::AtomicFixnum.new(0)
      settings do
        provide "mapping_rescue", -> (context, exception) {
          error_count.increment
          context.logger.error "Encountered exception: #{exception}, total errors #{error_count}"
          if my_should_skip?(context, exception)
            context.skip!
          else
            raise exception
          end
        }
      end

  At present `mapping_rescue` only handles exceptions in running mapping/indexing logic, unexpected raises in readers or writers may not be caught here.

### Threads

* `processing_thread_pool` Number of threads in the main thread pool used for
   processing records with input rules. On JRuby or Rubinius, defaults to 1 less
   than the number of processors detected on your machine. On other ruby
   platforms, defaults to 1.

   **NOTE**: If your processing code isn't thread-safe, set to 0 or nil to
   disable thread pool and do all processing in main thread.

   Choose a pool size based on size of your machine, and complexity of your
   indexing rules. You might want to try different sizes and measure which works
   best for you. Probably no reason for it ever to be more than number of cores
   on indexing machine.


### Writing (general)

* `writer`: An object that implements the Traject Writer interface. If set, takes precedence over `writer_class_name`.

* `writer_class_name`: a Traject Writer class, used by indexer to send processed dictionaries off. Will be used if no explicit `writer` setting or `#writer=` is set. Default Traject::SolrJsonWriter, other writers for debugging or writing to files are also available. See Traject::Indexer for more info. Command line shortcut `-w`
* `output_file`: Output file to write to for operations that write to files: For instance the `marcout` command, or Writer classes that write to files, like Traject::JsonWriter. Has an shortcut `-o` on command line.

### Writing to solr

* `json_writer.pretty_print`: used by the JsonWriter, if set to true, will output pretty printed json (with added whitespace) for easier human readability. Default false.

* `solr.url`: URL to connect to a solr instance for indexing, eg http://example.org:8983/solr . Command-line short-cut `-u`. (Can include embedded HTTP basic auth as eg `http://user:pass@example.org/solr`)

* `solr.version`: Set to eg "1.4.0", "4.3.0"; currently un-used, but in the future will control some default settings, and/or sanity check and warn you if you're doing something that might not work with that version of solr. Set now for help in the future.

* `solr_writer.batch_size`: size of batches that SolrJsonWriter will send docs to Solr in. Default 100. Set to nil, 0, or 1, and SolrJsonWriter will do one http transaction per document, no batching.

* `solr_writer.commit_on_close`: default false, set to true to have the solr writer send an explicit commit message to Solr after indexing.

* `solr_writer.thread_pool`: defaults to 1 (single bg thread). A thread pool is used for submitting docs to solr. Set to 0 or nil to disable threading. Set to 1, there will still be a single bg thread doing the adds. May make sense to set higher than number of cores on your indexing machine, as these threads will mostly be waiting on Solr. Speed/capacity of your solr might be more relevant. Note that processing_thread_pool threads can end up submitting to solr too, if solr_json_writer.thread_pool is full.

* `solr_writer.basic_auth_user`, `solr_writer.basic_auth_password`: Not set by default but when both are set the default writer is configured with basic auth. You can also just embed basic
auth credentials in `solr.url` using standard URI syntax.


### Dealing with MARC data

* `marc_source.type`: default 'binary'. Can also set to 'xml' or (not yet implemented todo) 'json'. Command line shortcut `-t`
* `marcout.allow_oversized`: Used with `-x marcout` command to output marc when outputting as ISO 2709 binary, set to true or string "true", and the MARC::Writer will have  allow_oversized=true set, allowing oversized records to be serialized with length bytes zero'd out -- technically illegal, but can be read by MARC::Reader in permissive mode.

### Logging and progress

* `debug_ascii_progress`: true/'true' to print ascii characters to STDERR indicating progress. Yes, this is fixed to STDERR, regardless of your logging setup.
  * `.` for every batch of records read and parsed
  * `^` for every batch of records batched and queued for adding to solr (possibly in thread pool)
  * `%` for completing of a Solr 'add'
  * `!` when threadpool for solr add has a full queue, so solr add is going to happen in calling queue -- means solr adding can't keep up with production.

* `log.file`: filename to send logging, or 'STDOUT' or 'STDERR' for those streams. Default STDERR

* `log.error_file`: Default nil, if set then all log lines of ERROR and higher will be _additionally_ sent to error file named.

* `log.format`: Formatting string used by Yell logger. https://github.com/rudionrails/yell/wiki/101-formatting-log-messages

* `log.level`:  Log this level and above. Default 'info', set to eg 'debug' to get potentially more logging info, or 'error' to get less. https://github.com/rudionrails/yell/wiki/101-setting-the-log-level

* `log.batch_size`: If set to a number N (or string representation), will output a progress line to log. (by default as INFO, but see log.batch_size.severity)

* `log.batch_size.severity`: If `log.batch_size` is set, what logger severity level to log to. Default "INFO", set to "DEBUG" etc if desired.

* 'logger': Ignore all the other logger settings, just pass a `Logger` compatible logger instance in directly.







