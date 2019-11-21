# Encoding: UTF-8

require 'test_helper'
require 'stringio'
require 'traject/delimited_writer'
require 'traject/csv_writer'

require 'csv'

describe "Delimited/CSV Writers" do

  before do
    @out                 = StringIO.new
    @settings            = {'output_stream' => @out, 'delimited_writer.fields' => 'four,one,two'}
    @context             = Struct.new(:output_hash).new
    @context.output_hash = {'one' => 'one', 'two' => %w[two1 two2], 'three' => 'three', 'four' => 'four'}
  end

  after do
    @out.close
  end

  describe "Traject::DelimitedWriter" do

    it "creates a dw with defaults" do
      dw = Traject::DelimitedWriter.new(@settings)
      assert_equal dw.delimiter, "\t"
      assert_equal dw.internal_delimiter, '|'
      assert_equal dw.edelim, ' '
      assert_equal dw.eidelim, '\\|'
    end

    it "respects different delimiter" do
      @settings['delimited_writer.delimiter'] = '^'
      dw                                      = Traject::DelimitedWriter.new(@settings)
      assert_equal dw.delimiter, '^'
      assert_equal dw.edelim, '\\^'
      assert_equal dw.internal_delimiter, '|'
    end

    it "outputs a header if asked to" do
      Traject::DelimitedWriter.new(@settings)
      assert_equal @out.string.chomp, %w[four one two].join("\t")
    end

    it "doesn't output a header if asked not to" do
      @settings['delimited_writer.header'] = 'false'
      Traject::DelimitedWriter.new(@settings)
      assert_empty @out.string
    end

    it "deals with multiple values" do
      dw = Traject::DelimitedWriter.new(@settings)
      dw.put @context
      assert_equal @out.string.split("\n").last, ['four', 'one', 'two1|two2'].join(dw.delimiter)
    end

    it "bails if delimited_writer.fields isn't set" do
      @settings.delete 'delimited_writer.fields'
      assert_raises(ArgumentError)  { Traject::DelimitedWriter.new(@settings) }
    end

  end

  describe "Traject::CSVWriter" do
    it "unsets the delimiter" do
      cw = Traject::CSVWriter.new(@settings)
      assert_nil cw.delimiter
    end

    it "writes the header" do
      Traject::CSVWriter.new(@settings)
      assert_equal @out.string.chomp, 'four,one,two'
    end

    it "uses the internal delimiter" do
      cw = Traject::CSVWriter.new(@settings)
      cw.put @context
      assert_equal @out.string.split("\n").last, ['four', 'one', 'two1|two2'].join(',')
    end

    it "produces complex output" do
      @context.output_hash = {
          'four' => ['Bill Clinton, Jr.', 'Jesse "the Body" Ventura'],
          'one' => 'Willard "Mitt" Romney',
          'two' => 'Dueber, Bill'
      }
      canonical = StringIO.new
      csv = CSV.new(canonical)

      csv_vals = [@context.output_hash['four'].join('|'), @context.output_hash['one'], @context.output_hash['two']]
      csv << csv_vals
      csv_output = canonical.string.chomp

      cw = Traject::CSVWriter.new(@settings)
      cw.put @context
      traject_csvwriter_output = @out.string.split("\n").last.chomp

      assert_equal(csv_output, traject_csvwriter_output)
    end
  end
end
