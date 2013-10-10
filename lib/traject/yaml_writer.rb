require 'traject/line_writer'
require 'yaml'

class Traject::YamlWriter < Traject::LineWriter
  def serialize(context)
    context.output_hash.to_yaml(:indentation=>3, :line_width => 78) + "\n\n"
  end
end

