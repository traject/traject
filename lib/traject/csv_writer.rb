require 'traject/delimited_writer'
require 'csv'

# A CSV-writer, for folks who like that sort of thing.
# Use DelimitedWriter for non-CSV lines (e.g., tab-delimited)
#
#

class Traject::CSVWriter < Traject::DelimitedWriter

  def initialize(*args)
    super
    self.delimiter = nil # Let CSV take care of it
  end

  def _write(data)
    @output_file << data
  end

  # Turn the output file into a CSV writer
  def open_output_file
    of = super
    CSV.new(of)
  end

  # Let CSV take care of the comma escaping
  def escape(x)
    x = x.to_s
    x.gsub! internal_delimiter, @eidelim
    x
  end


end
