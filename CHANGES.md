# Changes

## 3.0.0

### Changed/Backwards Incompatibilities

* Placeholder

* `map_record` now returns `nil` if record was skipped.

* The `Traject::Indexer` class no longer includes marc-specific settings and modules.
  * If you are using command-line `traject`, this should make no difference to you, as command-line now defaults to the new `Traject::Indexer::MarcIndexer` with those removed things.
  * If you are using Traject::Indexer programmatically and want those features, switch to using `Traject::Indexer::MarcIndexer`.
  * If neccessary, as a hopefully temporary backwards compat shim, call `Traject::Indexer.legacy_marc_mode!`, which injects the old marc-specific behavior into Traject::Indexer again, globally and permanently.

* Traject::Indexer::Settings no longer has it's own global defaults, Instead it can be given a set of defaults with #with_defaults, usually right after instantiation. To support different defaults for different Indexers.


### Added

* Placeholder

* Traject::Indexer#configure is available, and recommended instead of raw `instance_eval`. It just does an instance_eval, but is clearer and safer for future changes.

* traject command line can now take multiple input files. And underlying it, Traject::Indexer#process can take an array of input streams.

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
