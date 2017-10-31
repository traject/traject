# A sample traject configuration, save as say `traject_config.rb`, then
# run `traject -c traject_config.rb marc_file.marc` to index to
# solr specified in config file, according to rules specified in
# config file


# To have access to various built-in logic
# for pulling things out of MARC21, like `marc_languages`
require 'traject/macros/marc21_semantics'
extend  Traject::Macros::Marc21Semantics

# To have access to the traject marc format/carrier classifier
require 'traject/macros/marc_format_classifier'
extend Traject::Macros::MarcFormats


# In this case for simplicity we provide all our settings, including
# solr connection details, in this one file. But you could choose
# to separate them into antoher config file; divide things between
# files however you like, you can call traject with as many
# config files as you like, `traject -c one.rb -c two.rb -c etc.rb`
settings do
  provide "solr.url", "http://solr.somewhere.edu:8983/solr/corename"
end

# Extract first 001, then supply code block to add "bib_" prefix to it
to_field "id", extract_marc("001", :first => true) do |marc_record, accumulator, context|
  accumulator.collect! {|s| "bib_#{s}"}
end

# An exact literal string, always this string:
to_field "source",              literal("traject_test_last")

to_field "marc_display",        serialized_marc(:format => "binary", :binary_escape => false, :allow_oversized => true)

to_field "text",                extract_all_marc_values

to_field "text_extra_boost_t",  extract_marc("505art")

to_field "publisher_t",         extract_marc("260abef:261abef:262ab:264ab")

to_field "language_facet",      marc_languages

to_field "format",              marc_formats


to_field "isbn_t",              extract_marc("020a:773z:776z:534z:556z")
to_field "lccn",                extract_marc("010a")

to_field "material_type_display", extract_marc("300a", :separator => nil, :trim_punctuation => true)

to_field "title_t",             extract_marc("245ak")
to_field "title1_t",            extract_marc("245abk")
to_field "title2_t",            extract_marc("245nps:130:240abcdefgklmnopqrs:210ab:222ab:242abcehnp:243abcdefgklmnopqrs:246abcdefgnp:247abcdefgnp")
to_field "title3_t",            extract_marc("700gklmnoprst:710fgklmnopqrst:711fgklnpst:730abdefgklmnopqrst:740anp:505t:780abcrst:785abcrst:773abrst")

# Note we can mention the same field twice, these
# ones will be added on to what's already there. Some custom
# logic for extracting 505$t, but only from 505 field that
# also has $r -- we consider that more likely to be a titleish string
to_field "title3_t" do |record, accumulator|
  record.each_by_tag('505') do |field|
    if field['r']
      accumulator.concat field.subfields.collect {|sf| sf.value if sf.code == 't'}.compact
    end
  end
end

to_field "title_display",       extract_marc("245abk", :trim_punctuation => true, :first => true)
to_field "title_sort",          marc_sortable_title

to_field "title_series_t",      extract_marc("440a:490a:800abcdt:400abcd:810abcdt:410abcd:811acdeft:411acdef:830adfgklmnoprst:760ast:762ast")
to_field "series_facet",        marc_series_facet

to_field "author_unstem",       extract_marc("100abcdgqu:110abcdgnu:111acdegjnqu")

to_field "author2_unstem",      extract_marc("700abcdegqu:710abcdegnu:711acdegjnqu:720a:505r:245c:191abcdegqu")
to_field "author_display",      extract_marc("100abcdq:110:111")
to_field "author_sort",         marc_sortable_author


to_field "author_facet",        extract_marc("100abcdq:110abcdgnu:111acdenqu:700abcdq:710abcdgnu:711acdenqu", :trim_punctuation => true)

to_field "subject_t",           extract_marc("600:610:611:630:650:651avxyz:653aa:654abcvyz:655abcvxyz:690abcdxyz:691abxyz:692abxyz:693abxyz:656akvxyz:657avxyz:652axyz:658abcd")

to_field "subject_topic_facet", extract_marc("600abcdtq:610abt:610x:611abt:611x:630aa:630x:648a:648x:650aa:650x:651a:651x:691a:691x:653aa:654ab:656aa:690a:690x",
          :trim_punctuation => true, ) do |record, accumulator|
  #upcase first letter if needed, in MeSH sometimes inconsistently downcased
  accumulator.collect! do |value|
    value.gsub(/\A[a-z]/) do |m|
      m.upcase
    end
  end
end

to_field "subject_geo_facet",   marc_geo_facet
to_field "subject_era_facet",   marc_era_facet

# not doing this at present.
#to_field "subject_facet",     extract_marc("600:610:611:630:650:651:655:690")

to_field "published_display", extract_marc("260a", :trim_punctuation => true)

to_field "pub_date",          marc_publication_date

# An example of more complex ruby logic 'in line' in the config file--
# too much more complicated than this, and you'd probably want to extract
# it to an external routine to keep things tidy.
#
# Use traject's LCC to broad category routine, but then supply
# custom block to also use our local holdings 9xx info, and
# also classify sudoc-possessing records as 'Government Publication' discipline
to_field "discipline_facet",  marc_lcc_to_broad_category(:default => nil) do |record, accumulator|
  # add in our local call numbers
  Traject::MarcExtractor.cached("991:937").each_matching_line(record) do |field, spec, extractor|
      # we output call type 'processor' in subfield 'f' of our holdings
      # fields, that sort of maybe tells us if it's an LCC field.
      # When the data is right, which it often isn't.
    call_type = field['f']
    if call_type == "sudoc"
      # we choose to call it:
      accumulator << "Government Publication"
    elsif call_type.nil? ||
          call_type == "lc" ||
        Traject::Macros::Marc21Semantics::LCC_REGEX.match(field['a'])
      # run it through the map
      s = field['a']
      s = s.slice(0, 1) if s
      accumulator << Traject::TranslationMap.new("lcc_top_level")[s]
    end
  end


  # If it's got an 086, we'll put it in "Government Publication", to be
  # consistent with when we do that from a local SuDoc call #.
  if Traject::MarcExtractor.cached("086a").extract(record).length > 0
    accumulator << "Government Publication"
  end

  # uniq it in case we added the same thing twice with GovPub
  accumulator.uniq!

  if accumulator.empty?
    accumulator << "Unknown"
  end
end

to_field "instrumentation_facet",       marc_instrumentation_humanized
to_field "instrumentation_code_unstem", marc_instrument_codes_normalized

to_field "issn",                extract_marc("022a:022l:022y:773x:774x:776x", :separator => nil)
to_field "issn_related",        extract_marc("490x:440x:800x:400x:410x:411x:810x:811x:830x:700x:710x:711x:730x:780x:785x:777x:543x:760x:762x:765x:767x:770x:772x:775x:786x:787x", :separator => nil)

to_field "oclcnum_t",           oclcnum

to_field "other_number_unstem", extract_marc("024a:028a")

