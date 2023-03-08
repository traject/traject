require 'net/http'
require 'open-uri'
require 'csv'



CODELIST_NS = 'info:lc/xmlns/codelist-v1'

namespace :load_maps do

  desc "Load MARC geo codes by screen-scraping LC"
  task :marc_geographic do |task|
    require_nokogiri(task)

    source_url = "http://www.loc.gov/marc/geoareas/gacs_code.html"

    filename = ENV["OUTPUT_TO"] || File.expand_path("../../translation_maps/marc_geographic.yaml", __FILE__)
    file = File.open( filename, "w:utf-8" )

    $stderr.puts "Writing to `#{filename}` ..."

    html = Nokogiri::HTML(open(source_url).read)

    file.puts "# Translation map for marc geographic codes constructed by `rake load_maps:marc_geographic` task"    
    file.puts "# Scraped from #{source_url} at #{Time.now}"
    file.puts "# Intentionally includes discontinued codes."

    file.puts "\n"
    html.css("tr").each do |line|
      code = line.css("td.code").inner_text.strip
      unless code.nil? || code.empty?
        code.gsub!(/^\-/, '') # treat discontinued code like any other

        label = line.css("td[2]").inner_text.strip

        label.gsub!(/\n */, ' ') # get rid of newlines that file now sometimes contains, bah.
        label.gsub!("'", "''") # yaml escapes single-quotes by doubling them, weird but true. 

        file.puts "'#{code}': '#{label}'"
      end
    end
    $stderr.puts "Done."
  end

  desc "Load MARC language codes from LOC and SIL"
  task :marc_languages do |task|
    require_nokogiri(task)
    filename = ENV["OUTPUT_TO"] || File.expand_path("../../translation_maps/marc_languages.yaml", __FILE__)
    file = File.open(filename, "w:utf-8")
    $stderr.puts "Writing to `#{filename}` ..."
    file.puts("# Map Language Codes (in 008[35-37], 041) to User Friendly Term\r")

    marc_language_source_url = 'https://www.loc.gov/standards/codelists/languages.xml'
    doc = Nokogiri::XML(URI.parse(marc_language_source_url).open)
    marc_language_hash = doc.xpath('//codelist:language', codelist: CODELIST_NS)
                            .to_h do |node|
                              [node.xpath('./codelist:code/text()', codelist: CODELIST_NS).to_s,
                               node.xpath('./codelist:name/text()', codelist: CODELIST_NS).to_s]
                            end.reject { |key, _val| %w[und zxx].include? key }

    file.puts "\r"
    file.puts("# MARC language codes (including obsolete codes), from #{marc_language_source_url}\r\n")
    marc_language_hash.sort_by { |k, _v| k }.each do |key, value|
      file.puts("#{key}: #{escape_special_yaml_chars(value)}\r")
    end

    iso_639_3_url = 'https://iso639-3.sil.org/sites/iso639-3/files/downloads/iso-639-3.tab'
    parsed_url = URI.parse(iso_639_3_url)
    iso_languages = CSV.parse(parsed_url.read(encoding: 'UTF-8'), headers: true, col_sep: "\t", encoding: "UTF-8")
    iso_language_hash = iso_languages.to_h { |row| [row['Id'], row['Ref_Name']] }
                                     .reject { |key, _val| %w[und zxx].include? key }
                                     .reject { |key, _val| marc_language_hash.keys.include? key }
    file.puts "\r"
    file.puts("# ISO 639-3 codes, from #{iso_639_3_url}\r")
    iso_language_hash.sort_by { |k, _v| k }.each do |key, value|
      file.puts("#{key}: #{escape_special_yaml_chars(value)}\r")
    end
  end

  def require_nokogiri(task)
    require 'nokogiri'
  rescue LoadError
    $stderr.puts "\n  #{task&.name} task requires nokogiri"
    $stderr.puts "  Try `gem install nokogiri` and try again. Exiting...\n\n"
    exit 1
  end

  def escape_special_yaml_chars(string)
    string.match(/[\,\']/) ? %Q{"#{string}"} : string
  end
end
