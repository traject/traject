require 'library_stdnums'

$:.unshift '.'

require 'traject/macros/marc21_semantics'
extend  Traject::Macros::Marc21Semantics

################################
###### CORE FIELDS #############
################################

to_field "id", extract_marc("001", :first => true)
to_field "allfields", extract_all_marc_values do |r, acc|
  acc.replace [acc.join(' ')] # turn it into a single string
end

to_field 'fullrecord' do |rec, acc|
  acc << MARC::FastXMLWriter.single_record_document(rec)
end


################################
######## IDENTIFIERS ###########
################################

to_field 'oclc', oclcnum('035a:035z')


to_field 'isbn', extract_marc('020az', :separator=>nil) do |rec, acc|
     orig = acc.dup
     acc.map!{|x| StdNum::ISBN.allNormalizedValues(x)}
     acc << orig
     acc.flatten!
     acc.uniq!
end


to_field 'issn', extract_marc('022a:022l:022m:022y:022z:247x')
to_field 'isn_related', extract_marc("400x:410x:411x:440x:490x:500x:510x:534xz:556z:581z:700x:710x:711x:730x:760x:762x:765xz:767xz:770xz:772x:773xz:774xz:775xz:776xz:777x:780xz:785xz:786xz:787xz")



to_field 'sudoc', extract_marc('086az')
to_field "lccn", extract_marc('010a')
to_field 'rptnum', extract_marc('088a')

to_field 'barcode', extract_marc('974a')

################################
######### AUTHOR FIELDS ########
################################

# We need to skip all the 710 with a $9 == 'WaSeSS'

to_field 'mainauthor', extract_marc('100abcd:110abcd:111abc')
to_field 'mainauthor_role', extract_marc('100e:110e:111e', :trim_punctuation => true)
to_field 'mainauthor_role', extract_marc('1004:1104:1114', :translation_map => "ht/relators")


################################
########## TITLES ##############
################################

# For titles, we want with and without

to_field 'title',     extract_marc_filing_version('245abdefgknp', :include_original => true)
to_field 'title_a',   extract_marc_filing_version('245a', :include_original => true)
to_field 'title_ab',  extract_marc_filing_version('245ab', :include_original => true)
to_field 'title_c',   extract_marc('245c')

to_field 'vtitle',    extract_marc('245abdefghknp', :alternate_script=>:only, :trim_punctuation => true, :first=>true)


# Sortable title
to_field "titleSort", marc_sortable_title


to_field "title_top", extract_marc("240adfghklmnoprs0:245abfgknps:247abfgknps:111acdefgjklnpqtu04:130adfgklmnoprst0")
to_field "title_rest", extract_marc("210ab:222ab:242abnpy:243adfgklmnoprs:246abdenp:247abdenp:700fgjklmnoprstx03:710fgklmnoprstx03:711acdefgjklnpqstux034:730adfgklmnoprstx03:740anp:765st:767st:770st:772st:773st:775st:776st:777st:780st:785st:786st:787st:830adfgklmnoprstv:440anpvx:490avx:505t")
to_field "series", extract_marc("440ap:800abcdfpqt:830ap")
to_field "series2", extract_marc("490a")


###############################
#### Genre / geography / dates
###############################

to_field "genre", extract_marc('655ab')


# Look into using Traject default geo field
to_field "geographic" do |record, acc|
  marc_geo_map = Traject::TranslationMap.new("marc_geographic")
  extractor_043a  = MarcExtractor.cached("043a", :separator => nil)
  acc.concat(
    extractor_043a.extract(record).collect do |code|
      # remove any trailing hyphens, then map
      marc_geo_map[code.gsub(/\-+\Z/, '')]
    end.compact
  )
end

to_field 'era', extract_marc("600y:610y:611y:630y:650y:651y:654y:655y:656y:657y:690z:691y:692z:694z:695z:696z:697z:698z:699z")


# country from the 008; need processing until I fix the AlephSequential reader
to_field "country_of_pub" do |r, acc|
  country_map = Traject::TranslationMap.new("ht/country_map")
  if r['008']
    [r['008'].value[15..17], r['008'].value[17..17]].each do |s|
      next unless s # skip if the 008 just isn't long enough
      country = country_map[s.gsub(/[^a-z]/, '')]
      if country
        acc << country
      end
    end
  end
end

# Also add the 752ab
to_field "country_of_pub", extract_marc('752ab')



################################
########### MISC ###############
################################

to_field "publisher", extract_marc('260b:264|*1|:533c')
to_field "edition", extract_marc('250a')

to_field 'language', marc_languages("008[35-37]:041a:041d:041e:041j")
to_field 'language008', extract_marc('008[35-37]') do |r, acc|
  acc.reject! {|x| x !~ /\S/} # ditch only spaces
  acc.uniq!
end
