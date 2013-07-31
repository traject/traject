require 'net/http'
require 'open-uri'




namespace :load_maps do

  desc "Load MARC geo codes by screen-scraping LC"
  task :marc_geographic do
    begin
      require 'nokogiri'
    rescue LoadError => e
      $stderr.puts "\n  load_maps:marc_geographic task requires nokogiri"
      $stderr.puts "  Try `gem install nokogiri` and try again. Exiting...\n\n"
      exit 1
    end

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
end
