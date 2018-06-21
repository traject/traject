require 'marc'
require 'json'
require 'zlib'


# Read newline-delimited JSON file, where each line is a marc-in-json string.
# UTF-8 encoding is required.

class Traject::NDJReader
  include Enumerable

  def initialize(input_stream, settings)
    @settings = settings
    @input_stream = input_stream
    if input_stream.respond_to?(:path) && /\.gz\Z/.match(input_stream.path)
      @input_stream = Zlib::GzipReader.new(@input_stream, :external_encoding => "UTF-8")
    end
  end

  def logger
    @logger ||= (@settings[:logger] || Yell.new(STDERR, :level => "gt.fatal")) # null logger)
  end

  def each
    unless block_given?
      return enum_for(:each)
    end

    @input_stream.each_with_index do |json, i|
      begin
        yield MARC::Record.new_from_hash(JSON.parse(json))
      rescue Exception => e
        self.logger.error("Problem with JSON record on line #{i}: #{e.message}")
      end
    end
  end

end


