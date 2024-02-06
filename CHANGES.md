# Changes

## NEXT

*

## 3.8.2

Bug fix for the `#filing_version` logic, which was incorrectly assuming the 
first subfield in a field would hold content (e.g., `$a`) and thus failed
when it held a pointer to a linking field (e.g., `$6 245-01`)

```


## 3.8.1

Ugh. Forgot about Jruby 9.1 problem with bundler 2. Changing the requirement back. 

## 3.8.0

SolrJsonWriter: HTTPClient should use OS certs instead of packaged ones

HTTPClient, for whatever reason, prefers its own packaged certs, which are now years out of date
and don't work with Let's Encrypt.

This changes the code to prefer the OS certs, which can be overridden by setting
`solr_json_writer.use_packaged_certs` to `true` or `"true"`. 

## 3.7.0

* Add two new transformation macros, `Traject::Macros::Transformation.delete_if` and `Traject::Macros::Transformations.select`.

## 3.6.0

* Tiny backward compat changes for ruby 3.0 compat. https://github.com/traject/traject/pull/263

* Allow gem `http` 5.x in gemspec. https://github.com/traject/traject/pull/269

## 3.5.0

* `traject -v` and `traject -h` correctly return 0 exit code indicating success.

* upgrade to slop gem  4.x, which carries with it a slightly different format of human-readable command-line arg errors, should be otherwise invisible.

* the SolrJsonWriter now supports HTTP basic auth credentials embedded in `solr.url` or `solr.update_url`, eg `http://user:pass@example.org/solr` https://github.com/traject/traject/pull/262


## 3.4.0

* XML-mode `extract_xpath` now supports extracting attribute values with xpath @attr syntax.

## 3.3.0

* `Traject::Macros::Marc21Semantics.publication_date` now gets date from 264 before 260. https://github.com/traject/traject/pull/233

* Allow hashie 4.x in gemspec https://github.com/traject/traject/pull/234

* Allow `http` gem 4.x versions. https://github.com/traject/traject/pull/236

* Can now call class-level Indexer.configure multiple times https://github.com/sciencehistory/scihist_digicoll/pull/525

## 3.2.0

* NokogiriReader has a "nokogiri.strict_mode" setting. Set to true or string 'true' to ask Nokogori to parse in strict mode, so it will immediately raise on ill-formed XML, instead of nokogiri's default to do what it can with it. https://github.com/traject/traject/pull/226

* SolrJsonWriter

  * Utility method `delete_all!` sends a delete all query to the Solr URL endpoint. https://github.com/traject/traject/pull/227

  * Allow basic auth configuration of the default http client via `solr_writer.basic_auth_user` and `solr_writer.basic_auth_password`. https://github.com/traject/traject/pull/231


## 3.1.0

### Added

* Context#add_output is added, convenient for custom ruby code.

        each_record do |record, context|
           context.add_output "key", something_from(record)
        end

  https://github.com/traject/traject/pull/220

* SolrJsonWriter

  * Class-level indexer configuration, for custom indexer subclasses, now available with class-level `configure` method. Warning, Indexers are still expensive to instantiate though. https://github.com/traject/traject/pull/213

  * SolrJsonWriter has new settings to control commit semantics. `solr_writer.solr_update_args` and `solr_writer.commit_solr_update_args`, both have hash values that are Solr update handler query params. https://github.com/traject/traject/pull/215

  * SolrJsonWriter has a `delete(solr-unique-key)` method. Does not currently use any batching or threading. https://github.com/traject/traject/pull/214

  * SolrJsonWriter, when MaxSkippedRecordsExceeded is raised, it will have a #cause that is the last error, which resulted in MaxSkippedRecordsExceeded. Some error reporting systems, including Rails, will automatically log #cause, so that's helpful. https://github.com/traject/traject/pull/216

  * SolrJsonWriter now respects a `solr_writer.http_timeout` setting, in seconds, to be passed to HTTPClient instance. https://github.com/traject/traject/pull/219

  * Only runs thread pool shutdown code (and logging) if there is a `solr_writer.batch_size` greater than 0. Keep it out of the logs if it was a no-op anyway.

  * Logs at DEBUG level every time it sends an update request to solr

* Nokogiri dependency for the NokogiriReader increased to `~> 1.9`. When using Jruby `each_record_xpath`, resulting yielded documents may have xmlns declarations on different nodes than in MRI (and previous versions of nokogiri), but we could find now way around this with nokogiri >= 1.9.0. The documents should still be semantically equivalent for namespace use. This was necessary to keep JRuby Nokogiri XML working with recent Nokogiri releases.  https://github.com/traject/traject/pull/209

* LineWriter guesses better about when to auto-close, and provides an optional explicit setting in case it guesses wrong. (thanks @justinlittman) https://github.com/traject/traject/pull/211

* Traject::Indexer will now use a Logger(-compatible) instance passed in in setting 'logger' https://github.com/traject/traject/pull/217

## 3.0.0

### Changed/Backwards Incompatibilities

* JRuby traject no longer includes `traject-marc4j_reader` as a dependency or default reader, although it may provide faster MARC-XML reading on JRuby. To use it manually, see https://github.com/traject/traject-marc4j_reader . See https://github.com/traject/traject/pull/187

* `map_record` now returns `nil` if record was skipped.

* The `Traject::Indexer` class no longer includes marc-specific settings and modules.
  * If you are using command-line `traject`, this should make no difference to you, as command-line now defaults to the new `Traject::Indexer::MarcIndexer` with those removed things.
  * If you are using Traject::Indexer programmatically and want those features, switch to using `Traject::Indexer::MarcIndexer`.
  * If neccessary, as a hopefully temporary backwards compat shim, call `Traject::Indexer.legacy_marc_mode!`, which injects the old marc-specific behavior into Traject::Indexer again, globally and permanently.

* Traject::Indexer::Settings no longer has it's own global defaults, Instead it can be given a set of defaults with #with_defaults, usually right after instantiation. To support different defaults for different Indexers.

* SolrJsonWriter now assumes an /update/json convenience url is available in solr instead of trying to verify it.  If you are using an older Solr (before 4?) or otherwise want a different update url, just use setting `solr.update_url`


### Added

* Traject::Indexer#configure is available, and recommended instead of raw `instance_eval`. It just does an instance_eval, but is clearer and safer for future changes.

* traject command line can now take multiple input files. And underlying it, Traject::Indexer#process can take an array of input streams.

* There is now a built-in mode for XML source records, see docs at [xml.md](./doc/xml.md)

* new setting `mapping_rescue` is available, to supply custom logic for handling errors. See docs at [settings.md](../doc/settings.md)

* Call Traject::ThreadPool.disable_concurrency! to force all pool sizes to be 0, and work to be performed inline. All threading will be disabled.

* `to_field` can now take an array as a first argument, to send values to multiple fields mentioned, eg:

      to_field ["field1", "field2"], extract_marc("240")

* `to_field` can take multiple transformation procs (all with the same form). https://github.com/traject/traject/pull/153

* There is a new set of standard transformation macros included in `Traject::Indexer`, from [Traject::Macros::Transformation](./lib/traject/macros/transformation.rb). It includes an extraction of previous/existing arguments from `marc_extract`, along with some additional stuff. , in [Traject::Macros::Transformations]. https://github.com/traject/traject/pull/154
  * This is the new preferred way to do post-processing with the `marc_extract` options, but the existing options are not deprecated and there is no current plan for them to be removed.
  * before:

        to_field "some_field", extract_marc("800",
                                translation_map: "marc_800_map",
                                allow_duplicates: true,
                                first: true,
                                default: "default value")
  * now preferred:

        to_field "some_field", extract_marc("800", allow_duplicates: true),
            translation_map("marc_800_map"),
            first_only,
            default("default value")

    (still need `allow_duplicates: true` cause extract_marc defaults to false, but see also `unique` macro)

  * So, these transformation steps can now be used with non-MARC formats as well. See also new transformation macros: `strip`, `split`, `append`, `prepend`, `gsub`, and `transform`. And for MARC use, `trim_punctuation`.


* Traject::Indexer new api, for more convenient programmatic/embedded use.

  * `Traject::Indexer.new` takes a block for config

  * `Traject::Indexer#process_record`

  * `Traject::Indexer#process_with`

  * `Traject::Indexer#complete` and `#run_after_processing_steps` public API.

* `Traject::SolrJsonWriter#flush`, flush to solr without closing, may be useful for direct programmatic use.

* Traject::Indexer sub-classes can implement a #source_record_id_proc, which is passed to Context, for source-format-specific logic for getting an ID to use in logging.

* command line takes an `-i` flag for choice of indexer.

## 2.3.4
  * Totally internal change to provide easier hooks into indexing process

## 2.3.3
  * Further squash use of capture-variabels ('$1', etc.)
    to try to work around the non-thread-safety of
    regexp in ruby
  * Fix a bug in trim_punctuation where trailing
    periods were being eliminated even if there
    was a short string before them (e.g., 'Jr.')
  * Begin to reorganize tests, starting with
    the Marc21 macros

## 2.3.2
  * Change to `extract_marc` to work around a threadsafe problem in JRuby/MRI where
    regexps were unsafely shared between threads. (@codeforkjeff)
  * Make trim-punctuation safe for non-just-ASCII text (thanks to @dunn and @redlibrarian)

## 2.3.1
  * Update README with more info about new nil-related options

## 2.3.0
  * Allow nil values, empty fields, and deduplication

    This adds three new settings (all of whose defaults reflect current behavior)

    * `allow_nil_values` (default: false). Allow nil values to be sent on to the writer
    * `allow_duplicate_values` (default: true). Allow duplicate values. Set to false to
      force only unique values.
    * `allow_empty_fields` (default: false). Default behavior is that the output hash
      doesn't even contain keys for a `to_field` which doesn't produce any values.
      Set to `true` to pass empty fields on to the writer (with the value being an empty array)

## 2.2.1
  * Had inadvertently broken use of arrays as extract_marc specifications. Fixed.

## 2.2.0
  * Change DebugWriter to be more forgiving (and informative) about missing record-id fields
  * Automatically require DebugWriter for easier use on the command line
  * Refactor MarcExtractor to be easier to read
  * Fix .travis file to actually work, and target more recent rubies.

## 2.1.0
  * update some docs (typos)
  * Make the indexer's `writer` r/w so it can be set at runtime (#110)
  * Allow `extract_marc` to be callable from anywhere (#111)
  * Add doc instructions/examples for programmatic Indexer use
  * _Much_ better error reporting; easier to find which record went wrong


## 2.0.2

* Guard against assumption of MARC data when indexing using SolrJsonWriter ([#94](https://github.com/traject-project/traject/issues/94))
* For MARC Records, try to use the production date when available ([#93](https://github.com/traject-project/traject/issues/93))

## 2.0.1

* Fix bad constant in logging ([#91](https://github.com/traject-project/traject/issues/91))

## 2.0.0

* Compatible with MRI/RBX
* Default to SolrJsonWriter
* Release separate MRI/JRuby gems

## 1.0

* First release
