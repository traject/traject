# Other traject command-line commands

The traject command line supporst a few other miscellaneous commands with
the "-x command" switch. The usual traject command line is actually
the `process` command, `traject -x process ...` is the same as leaving out
the `-x process`.

## Commit

`traject -x commit` will send a 'commit' message to the Solr server
specified in setting `solr.url`.  Other parts of configuration will
be ignored, but don't hurt.

    traject -x commit -s solr.url=http://some.com/solr

Or with a config file that includes a solr.url setting:

    traject -x commit -c config_file.rb

## marcout

The `marcout` command will skip all processing/mapping, and simply
serialize marc out to a file stream.

This is mainly useful when you're using a custom reader to read
marc from a database or something, but could also be used to
convert marc from one format to another or something.

Will write to stdout, or set the `output_file` setting (`-o` shortcut).

Set the `marcout.type` setting to 'xml' or 'binary' for type of output.
Or to `human` for human readable display of marc (that is not meant for
machine readability, but can be good for manual diagnostics.)

If outputing type binary, setting `marcout.allow_oversized` to
true or false (boolean or string), to pass that to the MARC::Writer.
If set to true, then oversized MARC records can still be serialized,
with length bytes zero'd out -- technically illegal, but can
be read by MARC::Reader in permissive mode. 

If you have MARC-XML *input*, you need to
set the `marc_source.type` setting to XML for xml input.

~~~bash
traject -x marcout somefile.marc -o output.xml -s marcout.type=xml
traject -x marcout -s marc_source.type=xml somefile.xml -c configuration.rb
~~~
