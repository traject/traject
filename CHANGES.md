# Changes

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
  * Had inadverntantly broken use of arrays as extract_marc specifications. Fixed.
  
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
