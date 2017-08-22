require 'test_helper'
require 'tempfile'

describe "Traject::Indexer#load_config_path" do
  before do
    @indexer = Traject::Indexer.new
  end

  describe "with bad path" do
    it "raises ENOENT on non-existing path" do
      assert_raises(Errno::ENOENT) { @indexer.load_config_file("does/not/exist.rb") }
    end
    it "raises EACCES on non-readable path" do
      file = Tempfile.new('traject_test')
      FileUtils.chmod("ugo-r", file.path)

      assert_raises(Errno::EACCES) { @indexer.load_config_file(file.path) }

      file.unlink
    end
  end

  describe "with good config provided" do
    before do
      @config_file = tmp_config_file_with(%Q{
        settings do
          provide "our_key", "our_value"
        end
        to_field "literal", literal("literal")
      })      
    end
    after do
      @config_file.unlink
    end


    it "loads config file by path (as a String)" do
      @indexer.load_config_file(@config_file.path)

      assert_equal "our_value", @indexer.settings["our_key"]
    end

    it "loads config file by path (as a Pathname)" do
      @indexer.load_config_file(Pathname.new(@config_file.path))

      assert_equal "our_value", @indexer.settings["our_key"]
    end
  end

  describe "with error in config" do
    after do
      @config_file.unlink if @config_file
    end

    it "raises good error on SyntaxError type" do
      @config_file = tmp_config_file_with(%Q{
        puts "foo"
        # Intentional syntax error missing comma
        to_field "foo" extract_marc("245")
      }) 

      e = assert_raises(Traject::Indexer::ConfigLoadError) do
        @indexer.load_config_file(@config_file.path)
      end

      assert_kind_of SyntaxError, e.original
      assert_equal @config_file.path, e.config_file
      assert_equal 4,  e.config_file_lineno
    end

    it "raises good error on StandardError type (when passing String)" do
      @config_file = tmp_config_file_with(%Q{
        # Intentional non-syntax error, bad extract_marc spec
        to_field "foo", extract_marc("#%^%^%^")
      }) 

      e = assert_raises(Traject::Indexer::ConfigLoadError) do
        @indexer.load_config_file(@config_file.path)
      end

      assert_kind_of StandardError, e.original
      assert_equal @config_file.path, e.config_file
      assert_equal 3,  e.config_file_lineno
    end

    it "raises good error on StandardError type (when passing Pathname)" do
      @config_file = tmp_config_file_with(%Q{
        # Intentional non-syntax error, bad extract_marc spec
        to_field "foo", extract_marc("#%^%^%^")
      }) 

      e = assert_raises(Traject::Indexer::ConfigLoadError) do
        @indexer.load_config_file(Pathname.new(@config_file.path))
      end

      assert_kind_of StandardError, e.original
      assert_equal @config_file.path, e.config_file
    end
  end


  def tmp_config_file_with(str)
    file = Tempfile.new('traject_test_config')
    file.write(str)
    file.rewind

    return file
  end
end
