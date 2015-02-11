require 'traject/line_writer'

# A simple line writer that uses configuration to determine
# how to produce a tab-delimited file
#
# Appropos settings:
#
# * output_file  -- the file to write to
# * output_stream -- the stream to write to, if defined and output_file is not
# * delimited_writer.delimiter  -- What to separate fields with; default is tab
# * delimited_writer.internal_delimiter -- Delimiter _within_ a field, for multiple
#   values. Default is pipe ( | )
# * delimited_writer.fields -- comma-separated list of the fields to output
# * delimited_writer.header (true/false) -- boolean that determines if we should output a header row. Default is true
# * delimited_writer.escape -- If a value actually contains the delimited or internal_delimiter, what to do?
#   If unset, will follow the procedure below. If set, will turn it into the character(s) given
#
#
# If `delimited_writer.escape` is not set, the writer will automatically
# escape delimiters/internal_delimiters in the following way:
#  * If the delimiter is a tab, replace tabs in values with a single space
#  * If the delimiter is anything else, prefix it with a backslash

class Traject::DelimitedWriter < Traject::LineWriter

  attr_reader :delimiter,  :internal_delimiter, :edelim, :eidelim
  attr_accessor :header

  def initialize(settings)
    super

    # fields to output

    begin
      @fields = settings['delimited_writer.fields'].split(",")
    rescue NoMethodError => e
    end

    if e or @fields.empty?
      raise ArgumentError.new("#{self.class.name} must have a comma-delimited list of field names to output set in setting 'delimited_writer.fields'")
    end

    self.delimiter = settings['delimited_writer.delimiter'] || "\t"
    self.internal_delimiter = settings['delimited_writer.internal_delimiter'] || '|'
    self.header = settings['delimited_writer.header'].to_s != 'false'

    # Output the header if need be
    write_header if @header
  end

  def escaped_delimiter(d)
    return nil if d.nil?
    d == "\t" ? ' ' : '\\' + d
  end

  def delimiter=(d)
    @delimiter = d
    @edelim = escaped_delimiter(d)
    self
  end

  def internal_delimiter=(d)
    @internal_delimiter = d
    @eidelim =  escaped_delimiter(d)
  end




  def write_header
    _write(@fields)
  end

  def _write(data)
    output_file.puts(data.join(delimiter))
  end

  # Get the output values out of the context
  def raw_output_values(context)
    context.output_hash.values_at(*@fields)
  end

  # Escape the delimiters in whatever way has been defined
  def escape(x)
    x = x.to_s
    x.gsub! @delimiter, @edelim if @delimiter
    x.gsub! @internal_delimiter, @eidelim
    x
  end


  # Derive actual output field values from the raw values
  def output_values(raw)
    raw.map do |x|
      if x.is_a? Array
        x.map!{|s| escape(s)}
        x.join(@internal_delimiter)
      else
        escape(x)
      end
    end
  end

  # Spit out the escaped values joined by the delimiter
  def serialize(context)
    output_values(raw_output_values(context))
  end


end
