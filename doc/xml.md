# Traject use with XML

The [NokogiriIndexer](../lib/traject/nokogiri_indexer.md) is a Traject::Indexer subclass with some defaults for XML use. It has "nokogiri" in the name, because it's based around [nokogiri](https://github.com/sparklemotion/nokogiri) objects as source records in the traject pipeline.

It by default uses the NokogiriReader to read XML and read Nokogiri::XML::Documents, and includes the NokogiriMacros mix-in, with some macros for operating on Nokogiri::XML::Documents.

Plese notice that the recommened mechanism to parse MARC XML files with Traject is via the `-t` parameter (or the via the `provide "marc_source.type", "xml"` setting). The documentation in this page is for those parsing other (non MARC) XML files.

## On the command-line

You can tell the traject command-line to use the NokogiriIndexer with the `-i xml` flag:


```bash
traject -i xml -c some_appropriate_config some/path/*.xml
traject -i xml -c some_appropriate_config specific_file.xml
```

## In your config files

### Choosing your source record object

By default, each input XML file will be yielded as a source record into the traject pipeline. If you have things stored one-record-per-xml-document, that's just fine.

Frequently, we instead have an XML document which has sub-nodes that we'd like to treat as individual records in the pipeline.  Use the setting `nokogiri.each_record_xpath` for this.

If your xpath to slice into source records includes namespaces, you need to register them with `nokogiri.namespaces`.  For instance, to send one page of responses from an OAI-PMH server through traject, with OAI-PMH record being sliced into a separate traject source record:

```ruby
provide "nokogiri.namespaces", {
  "oai" => "http://www.openarchives.org/OAI/2.0/",
  "dc" => "http://purl.org/dc/elements/1.1/",
  "oai_dc" => "http://www.openarchives.org/OAI/2.0/oai_dc/"
}

provide "nokogiri.each_record_xpath", "//oai:record"
```

### using extract_xpath to get values

Generally with XML source, you'll want to extract individual pieces of text to index with traject. You do that with the `extract_xpath` macro.  You can use namespaces registered with the `nokogiri.namespaces` setting.

```ruby
to_field "title", extract_xpath("//dc:title")
```

The documents yielded to the pipeline will have the node selected by `each_record_xpath` as the root node, so if you want to use an absolute rather than relative xpath (which may likely be faster) in our OAI-PMH example, it might look like this:

```ruby
to_field "title", extract_xpath("/oai:record/oai:metadata/oai:dc/dc:title")
```

You can also provide prefix->namespace mappings in an individual `extract_xpath` call, to override or add to what was in `nokogiri.namespaces`, with the `ns` keyword argument:

```ruby
to_field "title", extract_xpath("/oai:record/oai:metadata/oai:dc/dc:title", ns: {
  "oai" => "http://www.openarchives.org/OAI/2.0/",
  "dc" => "http://purl.org/dc/elements/1.1/",
  "oai_dc" => "http://www.openarchives.org/OAI/2.0/oai_dc/"
})
```

If you are accessing a nokogiri method directly, like in `some_record.xpath`, the registered default namespaces aren't known by nokogiri -- but they are available in the indexer as `default_namespaces`, so can be referenced and passed into the nokogiri method:

```ruby
each_record do |record|
   log( record.xpath("//dc:title"), default_namespaces )
end
```

You can use all the standard transforation macros in Traject::Macros::Transformation:

```ruby
to_field "something", extract_xpath("//value"), first_only, translation_map("some_map"), default("no value")
```

### selecting attribute values

Just works, using xpath syntax for selecting an attribute:


```ruby
# gets status value in:  <oai:header status="something">
to_field "status", extract_xpath("//oai:record/oai:header/@status")
```


### selecting non-text nodes

Let's say our traject source records are nokogiri documents representing XML like this:

```xml
<person>
  <name>
    <given>Juan</given>
    <surname>Garcia</surname>
  </name>
</person>
```

And let's say we do:

```ruby
to_field "name", extract_xpath("//name")
```

We've selected an XML node that does not just contain text, but other sub-nodes. What will end up in the traject accumulator, and sent out to Solr index or other output? By default `extract_xpath` will extract only text nodes, in order found in source document, space-separated. So you'd get `"Juan Garcia"` above. Do note that is dependent on source element order.

Which might be quite fine, especially if you are putting this into an indexed field in a use where order may not be that important, or source order is exactly what you want.

You can instead tell `extract_xpath` `to_text: false` to have it put the actual Nokogiri::XML::Node selected into the accumulator, perhaps for further processing to transform it to text yourself:

```ruby
to_field "name", extract_xpath("//name", to_text: false) do |record, accumulator|
  accumulator.map! do |xml_node|
    "#{xml_node.at_path('./surname')}, #{xml_node.at_path('./given')}"
  end
end
```

If you call with `to_text: false`, and just leave the `Nokogiri::XML::Node`s on the accumulator, the default SolrJsonWriter will end up casting the to strings with `to_s`, which will serialize them to XML, which may be just what you want if you want to put serialized XML into a Solr field. To have more control over the serialization, you may want to use a transforation step similar to above.

## The OaiPmhReader

[OAI-PMH](http://www.openarchives.org/OAI/openarchivesprotocol.html) input seems to be a common use case for XML with traject.

You can certainly use your own tool to save OAI-PMH responses to disk, then process then as any other XML, as above.

But we also provide a Traject::OaiPmhReader that you may be interested in. You give it an OAI-PMH URL, it fetches via HTTP and follows resumptionTokens to send all records into traject pipeline.

This is somewhat experimental, please let us know if you find it useful, or find any problems with it.

    traject -i xml -r Traject::OaiPmhNokogiriReader -s oai_pmh.start_url="http://example.com/oai?verb=ListRecords&metadataPrefix=oai_dc" -c your_config.rb

See header comment doc on Traject::OaiPmhReader for more info.


## Performance, and JRuby

The current NokogiriReader reads the input with the DOM parser, `Nokogiri::XML.parse`. So will require memory proportional to size of input documents.

I experimented with streaming parsers and spent quite a few hours on it, but couldn't quite get it there in a way that made sense and had good performance.

The NokogiriReader parser should be relatively performant though, allowing you to process hundreds of records per second in MRI.

(There is a half-finished `ExperimentalStreamingNokogiriReader` available, but it is experimental, half-finished, may disappear or change in backwards compat at any time, problematic, not recommended for production use, etc.)

Note also that in Jruby, when using `each_record_xpath` with the NokogiriReader, the extracted individual documents may have xmlns declerations in different places than you may expect, although they will still be semantically equivalent for namespace processing. This is due to Nokogiri JRuby implementation, and we could find no good way to ensure consistent behavior with MRI. See: https://github.com/sparklemotion/nokogiri/issues/1875

### Jruby

It may be that nokogiri JRuby is just much slower than nokogiri MRI (at least when namespaces are involved?)  It may be that our workaround to a [JRuby bug involving namespaces on moving nodes](https://github.com/sparklemotion/nokogiri/issues/1774) doesn't help.

For whatever reason, in a simple test involving OAI-PMH schema-ed data, running under JRuby processes records only about 30% as quickly as running under MRI.

**JRuby is not recommended for XML use of traject at present.**
