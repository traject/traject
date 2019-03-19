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

Under standard use, a traject indexer is configured with mapping rules and other settings in a standalone configuration file. You can do this programmatically with `load_config_file`:

```ruby
indexer.load_config_file(path_to_config)
```

This can be convenient for config files you can use either from the command line, or programmatically. Or for allowing other staff roles to write config files separately. You can call `load_config_file` multiple times, and order may matter -- exactly the same as command line configuration files.

Alternately, you may instead want to do your configuration inline, using `configure` (which just does an `instance_eval`, but is encouraged for clarity and forwards-compatibility:

```ruby
indexer.configure do
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

### Configuring indexer subclasses

Indexing step configuration is historically done in traject at the indexer _instance_ level. Either programmatically or by applying a "configuration file" to an indexer instance.

But you can also define your own indexer sub-class with indexing steps built-in, using the class-level `configure` method.

This is an EXPERIMENTAL feature, implementation may change. https://github.com/traject/traject/pull/213

```ruby
class MyIndexer < Traject::Indexer
  configure do
    settings do
      provide "solr.url", Rails.application.config.my_solr_url
    end

    to_field "our_name", literal("University of Whatever")
  end
end
```

These setting and indexing steps are now "hard-coded" into that subclass. You can still provide additional configuration at the instance level, as normal. You can also make a subclass of that `MyIndexer` class, that will inherit configuration from MyIndexer, and can supply it's own additional class-level configuration too.

Note that due to how implementation is done, instantiating an indexer is still _relatively_ expensive. (Class-level configuration is only actually executed on instantiation). You will still get better performance by re-using a global instance of your indexer subclass, instead of, say, instantiating one per object to be indexed.

## Running the indexer

### process: probably not what you want

The standard command-line traject uses the `Indexer#process(io_stream)` method to invoke processing. While you can use this method programmatically, it makes some assumptions that may make it inconvenient for programmatic use:

* It automatically instantiates a reader and writer, and the reader and writer may not be safe to use more than once, so you can't call #process more than once for a given indexer instance. This also means you can't call it concurrently on the same indexer.

* It is optimized for millions+ records, for instance by default it uses internal threads, which you probably don't want -- and which can cause deadlock in some circumstances in a Rails5 app. You an set `processing_thread_pool` setting to `0` to ensure no additional threads created by indexer, but depending on the reader and writer involved, they may still be creating threads.

* It has what is probably excessive logging (and in some cases progress-bar output), assuming use as standalone command-line execution.

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

`process_record` should be safe to call concurrently on an indexer shared between threads -- so long as the configured writer is thread-safe, which all built-in writers are.

You can (and may want/need to) manually call `indexer.complete` to run after_processing steps, and
close/flush the writer.  After calling `complete`, the indexer can not be re-used for more `process_record` calls, as the writer has been closed.

### process_with: an in between option for easier programmatic use

`process_with` is sort of a swiss-army-knife of processing records with a Traject::Indexer.

You supply it with a reader and writer every time you call it, it does not use the instance-configured reader and writer. This means you can call it as many times as you want with the same indexer (as readers and writers are not always re-usable, and may not be safe to share between threads/invocations). `process_with` is also safe to call concurrently on an indexer shared between threads.

Since a ruby Array of source methods counts as a Traject "reader" (it has an `each` yielding records), you can simply pass it an array of input.  You can use the Traject::ArrayWriter as a "writer", which simply accumulates output Traject::Indexer::Contexts in memory. Or you can pass `process_with` a block instead of (or inaddition to!) a passed writer arg, as a sort of inline writer. The block will recieve one arg, a Context.

`process_with` does no logging, and does no concurrency (although the writer you are using may use multiple threads itself internally). It's a building block you can build whatever you like with.


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

By default, any exceptions raised in processing are simply raised -- terminating processing -- for you to rescue and deal with as you like. Instead, you can provide a `rescue_with` argument with a proc/lambda that will be triggered on an exception processing a record. The proc will be passed two args, the Traject::Indexer::Context and the exception. You can choose to re-raise the original exception or any other, or swallow it, or process it however you like.  If you do not raise, the indexer will continue processing subsequent records.

Skipped records are skipped, but you can hook into them with a `on_skipped` proc arg.

```ruby
indexer.process_with([record1, record2, record3],
                     Traject::ArrayWriter.new,
                     on_skipped: proc do |context|
                       puts "Skipped: #{context.record_inspect}"
                     end,
                     rescue_with: proc do |context, exception|
                      puts "Error #{exception} in #{context.record_inspect}, continuing to process more"
                     end)
```

`process_with` will *not* call any `after_processing` steps. Call them yourself if and when you want with `indexer.run_after_processing_steps`.

Some writers have a `close` method to finalize/flush output. `process_with` will not call it, you can call `writer.close` yourself -- after calling `close` on a writer, it can generally not be re-used.

## Indexer performance, re-use, and concurrency

While the `Traject::Indexer` has generally been tuned for high performance, this does not apply to creating and configuring an indexer.

In particular, `indexer.load_config_file(path_to_config)` is not going to be high-performance, as it requires touching the file system to find and load a config file. If you are creating lots of indexer instances throughout your program life, and doing so in a place where the indexer instantiation is a performance bottleneck, this may be a problem.

I looked into trying to make `load_config_file`-type functionality more performant, but have not yet found a great way.

You may want to consider instead creating one or more configured "global" indexers (likely in a class variable rather than a ruby global variable, although it's up to you), and re-using it throughout your program's life.  Since most reader-less uses of the Indexer are thread-safe, this should be safe to do even if in a situation (like a Rails app under many app server environments) where a global indexer could be used concurrently by multiple threads.

### Concurrency concerns

* Indexing rules must be thread-safe. They generally will be naturally, but if you are refering to external state, you have to use thread-safe data structures. [concurrent-ruby](https://github.com/ruby-concurrency/concurrent-ruby), which is already a dependency of traject, has a variety of useful thread-safe and concurrent data structures.

* Writers should be written in a thread-safe manner, assuming concurrent calls to `put`. The built-in Writers all should be. If you are writing a custom Writer, you should ensure it is thread-safe for concurrent calls to `put`.

* Readers, and the Indexer#process method, are not thread-safe. Which is why using Indexer#process, which uses a fixed reader, is not threads-safe, and why when sharing a global idnexer we want to use `process_record`, `map_record`, or `process_with` as above.

It ought to be safe to use a global Indexer concurrently in several threads, with the `map_record`, `process_record` or `process_with` methods -- so long as your indexing rules and writers are thread-safe, as they usually will be and always ought to be.

### An example

For the simplest case, we want to turn off all built-in traject concurrency in a "global" indexer we create, and then send records to.

```ruby
$traject_indexer = Traject::Indexer.new(
  # disable Indexer processing thread pool, to keep things simple and not interfering with Rails.
  "processing_thread_pool" => 0,
  "solr_writer.thread_pool" => 0, # writing to solr is done inline, no threads

  "solr.url" => "http://whatever",
  "writer_class" => "SolrJsonWriter",
  "solr_writer.batch_size" => 1, #send to solr for each record, no batching
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

### Rails concerns, and disabling concurrency

Rails will auto-load and re-load classes in typical development configuration. Rails 5 for the first time made dev-mode auto/re-loading concurrency safe, but at the cost of requiring _all_ code using threads to use Rails-specific APIs, or risk deadlock.

This makes things difficult for re-using non-rails-specific code that uses concurrency -- such as traject -- in a rails project.

For more information see the Rails guide on [Threading and code execution](http://guides.rubyonrails.org/threading_and_code_execution.html), and [this issue on concurrent-ruby](https://github.com/ruby-concurrency/concurrent-ruby/issues/585).

If you are using traject within Rails, and you have default dev-mode class auto/re-loading turned on, you may find that the execution locks up in a deadlock, involving Rails auto-loading.

One solution would be turning off Rails class reloading even in development, with `config.eager_loading = true` and `config.config.cache_classes = true`.

Another solution would be disabling all concurrency in Traject. You can do this with traject settings, but multiple settings may be required as different parts of traject each can use concurrency. For instance, as above, you need to set both `processing_thread_pool` and `solr_writer.thread_pool` to 0.

Alternately, you can call `Traject::ThreadPool.disable_concurrency!` -- this disables all multi-threaded concurrency in traject, process-wide and irrevocably.  This can also be useful for temporary debugging.

We may in the future explore making traject automatically use Rails concurrency API so concurrency can just work in Rails too, but it's a bit of a mess.
