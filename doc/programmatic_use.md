# Programmatic/Embedded Use of Traject

Traject was originally written with a core use case of batch-processing many (millions) of records as a stand-alone process, usually with the `traject` command-line.

However, people have also found it useful for programmatic use embedded within a larger application, including Rails apps. Here are some hints for how to use traject effectively programmatically:

## Initializing an indexer

The first arg to indexer constructor is an optional hash of settings, same settings you could set in configuration. Under programmatic use, it may be more convenient or more legible to set in constructor. Keys can be Strings or Symbols.

```ruby
indexer = Traject::Indexer.new("solr_writer.commit_on_close" => true)
```

Note that keys passed in as an initializer arg will "override" any settings set with `provide` in config.

## Configuring an indexer

Under standard use, a traject indexer is configured with mapping rules and other settings in a standalone configuration file. You can still do this with programmatic use if desired:

```ruby
indexer.load_config_file(path_to_config)
```

This can be convenient for config files you can use either from the command line, or programmatically. Or for allowing other staff roles to write config files separately. You can call `load_config_file` multiple times, and order may matter -- exactly the same as command line configuration files.

Alternately, you may instead want to do your configuration inline, using instance_eval:

```ruby
indexer.instance_eval do
  # you can choose to load config files this way
  load_config_file(path_to_config)

  to_field "whatever", extract_marc("800")
  after_processing do
    # whatever
  end
end
```

Whatever you might do in a traject config file is valid here, because this is exactly the method used when traject loads config files. This includes adding in macros with `extend SomeModule`. Again, you can do instance_eval multiple times, and order may matter, just like ordinary config files.

As a convenience, you can also pass a block to indexer constructor, that will be `instance_eval`d, intended for configuration:

```ruby
indexer = Traject::Indexer.new(settings) do
  to_field "whatever", extract_marc(whatever)
end
```

## Running the indexer

### process: probably not what you want

The standard command-line traject uses the `Indexer#process(io_stream)` method to invoke processing. While you can use this method programmatically, it makes some assumptions that may make it inconvenient for programmatic use:

* It automatically instantiates a reader and writer, and the reader and writer may not be safe to use more than once, so you can't call #process more than once for a given indexer instance.

* It is optimized for millions+ records, for instance by default it uses internal threads, which you probably don't want -- and which can cause deadlock in some circumstances in a Rails5 app. You an set `processing_thread_pool` setting to `0` to ensure no additional threads created by indexer, but depending on the reader and writer involved, they may still be creating threads.

* It has what is probably excessive logging (and in some cases progress-bar output), assuming use as a batch standalone job.

* It runs all `after_processing` steps, which you may not want in a few-records-at-a-time programmatic context.

As an alternative to the full high-volume pipeline in `#process`, several other methods
that do less, and are more easily composable, are available: `#map_record`, `#process_record`, and `#process_with`.


### map_record: just map a single record, handle transformed output yourself

Simplest of all, `#map_record` takes a single source record, and simply returns the output_hash
transformed from it. You don't get the full Context back, and it is your responsibility to do something with this output_hash. If the record was skipped, nil is returned. Exceptions
in processing are simply raised out of this method.

```ruby
output_hash = indexer.map_record(record)
```


### process_record: send a single record to instance writer

`#process_record` takes a single source record, sends it thorugh transformation, and sends the output the instance-configured writer. No logging, threading, or error handling is done for you. Skipped records will not be sent to writer. A `Traject::Indexer::Context` is returned from every call.

```ruby
context = indexer.process_record(source_record)
```

This method can be thought of as sending a single record through the indexer's pipeline and writer. For convenience, this is also aliased as `#<<`.

```ruby
indexer << source_record
```

You can (and may want/need to) manually call `indexer.complete` to run after_processing steps, and
close/flush the writer.  After calling `complete`, the indexer can not be re-used for more `process_record` calls, as the writer has been closed.

### process_with: an in between option for easier programmatic use

`process_with` is sort of a swiss-army-knife of processing records with a Traject::Indexer.

You supply it with a reader and writer every time you call it, it does not use the instance-configured reader and writer. This means you can call it as many times as you want with the same indexer (as readers and writers are not always re-usable, and may not be safe to share between threads/invocations).

Since a ruby Array of source methods counts as a Traject "reader" (it has an `each` yielding records), you can simply pass it an array of input.  You can use the Traject::ArrayWriter as a "writer", which simply accumulates output Traject::Indexer::Contexts in memory. Or you can pass `process_with` a block instead of (or inaddition to!) a passed writer arg, as a sort of inline writer. The block will recieve one arg, a Context.

`process_with` does no logging, and does no concurrency (although be careful if you are using a pre-existing Writer that may do it's own threaded concurrency). It's a building block you can build whatever you like with.


```ruby
writer = indexer.process_with([record1, record2, record3], Traject::ArrayWriter.new)
output_hashes = writer.values
output_contexts = writer.contexts
writer.clear! # if desired

# or

indexer.process_with([source_record, other_record]) do |context|
  puts "#{context.position}: #{context.output_hash}"
end
```

By default, any exceptions raised in processing are simply raised -- terminating processing -- for you to rescue and deal with as you like. Instead, you can provide a `rescue_with` argument with a proc/lambda that will be triggered on an exception processing a record. The proc will be passed two args, the Traject::Indexer::Context and the exception. You can choose to re-raise the exception or any other, or swallow it, or process it however you like.  If you do not raise, the indexer will continue processing subsequent records.

Skipped records are skipped, but you can hook into them with a `on_skipped` proc arg.

`process_with` will *not* call any `after_processing` steps. Call them yourself if and when you want with `indexer.run_after_processing_steps`.

## Indexer performance, re-use, and concurrency

While the `Traject::Indexer` has generally been tuned for high performance, this does not apply to creating and configuring an indexer.

In particular, `indexer.load_config_file(path_to_config)` is not going to be high-performance, as it requires touching the file system to find and load a config file. If you are creating lots of indexer instances throughout your program life, and doing so in a place where the indexer instantiation is a performance bottleneck, this may be a problem.

I looked into trying to make `load_config_file`-type functionality more performant, but have not yet found a great way.

You may want to consider instead creating one or more configured "global" indexers (likely in a class variable rather than a ruby global variable, although it's up to you), and re-using it throughout your program's life.  Since most reader-less uses of the Indexer are thread-safe, this should be safe to do even if in a situation (like a Rails app under many app server environments) where a global indexer could be used concurrently by multiple threads.

### Concurrency concerns

* Your indexing rules should generally be thread-safe, unless you've done something odd mutating state outside of what was passed in in the args, in the indexing rule.

* The built-in Writers should be thread-safe for concurrent uses of `put`, which is what matters for the API above. The SolrJsonWriter qualifies.

* Readers, and the Indexer#process method, are not thread-safe. So you will want to use `process_record`, `map_record`, or `process_with` as above, instead of an indexer-instance-configured Reader and #process.

### An example

For the simplest case, we want to turn off all built-in traject concurrency in a "global" indexer we create, and then send records to.

```ruby
$traject_indexer = Traject::Indexer.new(
  # disable Indexer processing thread pool, to keep things simple and not interfering with Rails.
  "processing_thread_pool" => 0,

  "solr.url" => "http://whatever",
  "writer_class" => "SolrJsonWriter",
  "solr_writer.batch_size" => 1, #send to solr for each record, no batching
  "solr_writer.thread_pool" => 0, # writing to solr is done inline, no threads
) do
  load_config_file("whatever/config.rb")
end

# Now, wherever you want, simply:

$traject_indexer << source_record
```
`<<` is an alias for `process_record`. Above will take the source record, process it, and send it to the writer -- which has been configured to immediately send the `add` to solr. All of this will be done in the caller thread, with no additional threads used.

If you'd like the indexing operation to be 'async' from wherever you are calling it (say, a model save), you may want to use your own concurrency/async logic (say a Concurrent::Future, or an ActiveJob) to execute the `$traject_indexer << source_record` -- no problem. We above disable concurrency inside of Traject so you can do whatever you want at your application layer instead.

Note that the SolrJsonWriter will _not_ issue `commit` commands to Solr -- your Solr autoCommit configuration is likely sufficient, but if you need a feature where SolrJsonWriter sends commits, let us know.

The above example will do a separate HTTP POST to Solr for every record, which may not be ideal performance-wise. (On the plus side, it should re-use persistent HTTP connections if your Solr server supports that, so making your Solr server support that could be of benefit). You may want to do something more complicated that batches things somehow -- you can possibly do that with various settings/patterns of use for SolrJsonWriter (see for instance SolrJsonWriter#flush), or perhaps you want to use `map_record` or `process_with` as primitives to build whatever you want on top:


```ruby
$indexer.process_with(array_of_one_or_more_records) do |context|
  # called for each output document
  do_whatever_you_want_with(context.output_hash)
end
```

For instance, [Sunspot](https://github.com/sunspot/sunspot) does some [fancy stuff](https://github.com/sunspot/sunspot/blob/0cfa5d2a27cac383127233b846e6fed63db1dcbc/sunspot/lib/sunspot/batcher.rb) to try and batch Solr adds within a given bounded context. Perhaps something similar could be done on top of traject API if needed.

