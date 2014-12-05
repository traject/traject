# Encoding: UTF-8

require 'test_helper'
require 'stringio'
require 'traject/delimited_writer'
require 'traject/csv_writer'

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
      dw.delimiter.must_equal "\t"
      dw.internal_delimiter.must_equal '|'
      dw.edelim.must_equal ' '
      dw.eidelim.must_equal '\\|'
    end

    it "respects different delimiter" do
      @settings['delimited_writer.delimiter'] = '^'
      dw                                      = Traject::DelimitedWriter.new(@settings)
      dw.delimiter.must_equal '^'
      dw.edelim.must_equal '\\^'
      dw.internal_delimiter.must_equal '|'
    end

    it "outputs a header if asked to" do
      dw = Traject::DelimitedWriter.new(@settings)
      @out.string.chomp.must_equal %w[four one two].join("\t")
    end

    it "doesn't output a header if asked not to" do
      @settings['delimited_writer.header'] = 'false'
      dw                                   = Traject::DelimitedWriter.new(@settings)
      @out.string.must_be_empty
    end

    it "deals with multiple values" do
      dw = Traject::DelimitedWriter.new(@settings)
      dw.put @context
      @out.string.split("\n").last.must_equal ['four', 'one', 'two1|two2'].join(dw.delimiter)
    end

    it "bails if delimited_writer.fields isn't set" do
      @settings.delete 'delimited_writer.fields'
      proc { Traject::DelimitedWriter.new(@settings) }.must_raise(ArgumentError)
    end

  end

  describe "Traject::CSVWriter" do
    it "unsets the delimiter" do
      cw = Traject::CSVWriter.new(@settings)
      cw.delimiter.must_be_nil
    end

    it "writes the header" do
      cw = Traject::CSVWriter.new(@settings)
      @out.string.chomp.must_equal 'four,one,two'
    end

    it "uses the internal delimiter" do
      cw = Traject::CSVWriter.new(@settings)
      cw.put @context
      @out.string.split("\n").last.must_equal ['four', 'one', 'two1|two2'].join(',')
    end

  end
end
