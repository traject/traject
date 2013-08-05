#require 'traject/macros/marc21'
#require 'traject/macros/basic'
#extend Traject::Macros::Marc21
#extend Traject::Macros::Basic

require 'traject/macros/marc21_semantics'
extend  Traject::Macros::Marc21Semantics

require 'traject/macros/marc_format_classifier'
extend Traject::Macros::MarcFormats

settings do
  #provide "solr.url", "http://catsolrmaster.library.jhu.edu:8985/solr/master_prod"

  provide "solr.url", "http://blacklight.mse.jhu.edu:8983/solr/prod"
  provide "solrj_writer.parser_class_name", "XMLResponseParser"

  provide "solrj_writer.commit_on_close", true

  #require 'traject/marc4j_reader'
  #store "reader_class_name", "Marc4JReader"
end

to_field "id", extract_marc("001", :first => true) do |marc_record, accumulator, context|
  accumulator.collect! {|s| "bib_#{s}"}

  # A way to intentionally add errors
  #if context.position % 10 == 0
    # intentionally add another one to error
  #  accumulator << "ANOTHER"
  #end

end

to_field "source",              literal("traject_test_last")

to_field "marc_display",        serialized_marc(:format => "binary", :binary_escape => false)

to_field "text",                extract_all_marc_values

to_field "text_extra_boost_t",  extract_marc("505art")

to_field "publisher_t",         extract_marc("260abef:261abef:262ab:264ab")

to_field "language_facet",      marc_languages

to_field "format",              marc_formats


to_field "isbn_t",              extract_marc("020a:773z:776z:534z:556z")
to_field "lccn",                extract_marc("010a")

to_field "material_type_display", extract_marc("300a", :seperator => nil, :trim_punctuation => true)

to_field "title_t",             extract_marc("245ak")
to_field "title1_t",            extract_marc("245abk")
to_field "title2_t",            extract_marc("245nps:130:240abcdefgklmnopqrs:210ab:222ab:242abcehnp:243abcdefgklmnopqrs:246abcdefgnp:247abcdefgnp")
to_field "title3_t",            extract_marc("700gklmnoprst:710fgklmnopqrst:711fgklnpst:730abdefgklmnopqrst:740anp:505t:780abcrst:785abcrst:773abrst")
to_field "title3_t" do |record, accumulator|
  # also add in 505$t only if the 505 has an $r -- we consider this likely to be
  # a titleish string, if there's a 505$r
  record.each_by_tag('505') do |field|
    if field['r']
      accumulator.concat field.subfields.collect {|sf| sf.value if sf.code == 't'}.compact
    end
  end
end

to_field "title_display",       extract_marc("245abk", :trim_puncutation => true, :first => true)
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
          :trim_puncutation => true, ) do |record, accumulator|
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

# LCC to broad class, start with built-in from marc record, but then do our own for local
# call numbers.
lcc_map = Traject::TranslationMap.new("lcc_top_level")
to_field "discipline_facet",  marc_lcc_to_broad_category(:default => nil) do |record, accumulator|
  # add in our local call numbers
  accumulator.concat(
    Traject::MarcExtractor.new(record, "991:937").collect_matching_lines do |field, spec, extractor|
        # we output call type 'processor' in subfield 'f' of our holdings
        # fields, that sort of maybe tells us if it's an LCC field.
        # When the data is right, which it often isn't.
      call_type = field['f']
      if call_type == "sudoc"
        # we choose to call it:
        "Government Publication"
      elsif call_type.nil? || call_type == "lc" || field['a'] =~ Traject::Macros::Marc21Semantics::LCC_REGEX
        # run it through the map
        s = field['a']
        s = s.slice(0, 1) if s
        lcc_map[s]
      else
        nil
      end
    end.compact
  )

  # If it's got an 086, we'll put it in "Government Publication", to be
  # consistent with when we do that from a local SuDoc call #.
  if Traject::MarcExtractor.extract_by_spec(record, "086a", :seperator =>nil).length > 0
    accumulator << "Government Publication"
  end

  accumulator.uniq!

  if accumulator.empty?
    accumulator << "Unknown"
  end
end

to_field "instrumentation_facet",       marc_instrumentation_humanized
to_field "instrumentation_code_unstem", marc_instrument_codes_normalized

to_field "issn",                extract_marc("022a:022l:022y:773x:774x:776x", :seperator => nil)
to_field "issn_related",        extract_marc("490x:440x:800x:400x:410x:411x:810x:811x:830x:700x:710x:711x:730x:780x:785x:777x:543x:760x:762x:765x:767x:770x:772x:775x:786x:787x", :seperator => nil)

to_field "oclcnum_t",           oclcnum

to_field "other_number_unstem", extract_marc("024a:028a")

