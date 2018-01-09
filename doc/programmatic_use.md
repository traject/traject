# Programmatic/Embedded Use of Traject

Traject was originally written with a core use case of processing many (millions) of records as a stand-alone process, usually with the `traject` command-line.

However, people have also found it useful for programmatic use embedded within a larger application, including Rails apps. Here are some hints for how to use traject effectively programmatically:

## Initialize an indexer

The first arg to indexer constructor is an optional hash of settings, same settings you could set in configuration. Under programmatic use, it may be more convenient or more legible to set in constructor. Keys can be Strings or Symbols.

```ruby
indexer = Traject::Indexer.new("solr_writer.commit_on_close" => true)
```

## Configuring an indexer

Under standard use, a traject indexer is configured with mapping rules and other settings in a standalone configuration file. You can still do this with programmatic use if desired:

```ruby
indexer.load_config_file(path_to_config)
```

This can be convenient for config files you can use either from the command line, or programmatically. Or for allowing other staff roles to write config files separately. You can call `load_config_file` multiple times, and order may matter -- exactly the same as command line configuration files.

Alternately, you may instead want to do your configuration inline, using instance_eval:

```ruby
indexer.instance_eval do
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

### process: may not be be convenient

The standard command-line traject uses the `Indexer#process(io_stream)` method to invoke processing. While you can use this method programmatically, it makes some assumptions that may make it inconvenient for programmatic use:

* It automatically instantiates a reader and writer, and the reader and writer may not be safe to use ore than once, so you can't count on calling #process more than once for a given indexer

* It is optimized for millions+ records, for instance by default it uses internal threads, which you probably don't want (and which can cause deadlock in some circumstances in a Rails5 app. (set `processing_thread_pool` setting to `0` to ensure no additional threads created by indexer. Depending on the reader and writer involved, they may still be creating threads).

* It has what is probably excessive logging (and in some cases progress-bar output), assuming use as a batch standalone job.

* It runs all `after_processing` steps, which you may not want in a few-records-at-a-time programmatic context.

### process_with: intended for easier programmatic use

The `Indexer#process_with` method is lighter-weight, makes fewer assumptions, and should be more suitable for embedded programmatic use, and, if desired, building out into larger constructs of your own.

`process_with` needs to be given a reader/source and writer every time it is called -- it does not use a instance-state-based reader or writer.

The `reader` can be any object with an `each` method returning source records. This includes a simple ruby Array of source records, or any instantiated traject Reader.

The `writer` can be any object with a `put` method that will take a Traject::Indexer::Context that is per-record output of transformations. The context has an `#output_hash` method that is simply the output hash. This includes any instantiated traject Writer. For convenience, there is built-in Traject::ArrayWriter which simply stores all output values and contexts given to it. (You may not want to use this with millions of output records, for obvious reasons).

```ruby
writer = indexer.process_with([record1, record2, record3], Traject::ArrayWriter.new)
output_hashes = writer.values
output_contexts = writer.contexts
writer.clear! # if desired
```

Instead of (or in addition to) using a writer/destination object, you can supply a block
that will be called with the post-transformation `Traject::Indexer::Context` for every
record (including skipped records! Check `context.skip?` if needed).

```ruby
indexer.process_with(source_records) do |context|
  unless context.skip?
    puts "#{context.position}: #{context.output_hash}"
  end
end
```

By default, any exceptions raised in processing are simply raised, for you to rescue and
deal with as you like. Instead, you can provide a `rescue` argument with a proc/lambda
that will be triggered on an exception processing a record. The proc/lambda you pass in:


  * Will be passed two arguments:
    1. `Traject::Indexer::Context`. From this you can get the `#source_record`, `#position`, and any `#output_hash` created before error.
    2. The Exception raised.

  * Can raise the original exception or any exception it wants, either of which will interupt the `process_with`. If your proc does not raise, `process_with` will silently continue to process subsequent records.

Notes:

* `process_with` does very little logging or progress status, do it yourself if you want it.

* `process_with` will _never_ use any additional threads, regardless of indexer settings. If you want threads, do them yourself with multiple invocations of `process_with`, with different records, in different threads. (You still should be aware of any concurrency behavior in any readers or writers you are using.)

* You can call `process_with` as many times as you like, and it should be thread safe to call `process_with` on a single indexer in multiple concurrent threads. You can keep a single global indexer if you like, and call `process_with` multiple times on it.
  * You should be careful sharing readers and writers passed as args between different threads though, unless you know the readers and writers are thread safe. Particular readers and writers also may not be safe to use more than once.

* `process_with` will *not* call any `after_processing` steps. Call them yourself if and when you want with `indexer.run_after_processing_steps`.

### map_record: simplest of all

Simplest of all, `#map_record` takes a single source record, and simply returns the output_hash
transformed from it. You don't get the full Context back, and it is your responsibility to do something with this output_hash. If the record was skipped, nil is returned. Exceptions
in processing are simply raised out of this method.

```ruby
output_hash = indexer.map_record(record)
```
