# Require as little as possible at top, so we can bundle require later
# if needed, before requiring anything from the bundle. Can't avoid slop
# though, to get our bundle arg out, sorry. 
require 'slop'

module Traject
  # The class that executes for the Traject command line utility.
  #
  # Warning, does do things like exit entire program on error at present.
  # You probably don't want to use this class for anything but an actual
  # shell command line, if you want to execute indexing directly, just
  # use the Traject::Indexer directly. 
  #
  # A CommandLine object has a single persistent Indexer object it uses
  class CommandLine
    # orig_argv is origina one passed in, remaining_argv is after destructive
    # processing by slop, still has file args in it etc.
    attr_accessor :orig_argv, :remaining_argv
    attr_accessor :slop, :options
    attr_accessor :indexer
    attr_accessor :console

    def initialize(argv=ARGV)
      self.console = $stderr

      self.orig_argv      = argv.dup
      self.remaining_argv = argv

      self.slop    = create_slop!
      self.options = parse_options(self.remaining_argv)
    end

    # Returns true on success or false on failure; may also raise exceptions;
    # may also exit program directly itself (yeah, could use some normalization)
    def execute
      if options[:version]
        self.console.puts "traject version #{Traject::VERSION}"
        return
      end
      if options[:help]
        self.console.puts slop.help
        return
      end

      # have to use Slop object to tell diff between
      # no arg supplied and no option -g given at all
      if slop.present? :Gemfile
        require_bundler_setup(options[:Gemfile])
      end

      # We require them here instead of top of file,
      # so we have done bundler require before we require these.
      require 'traject'
      require 'traject/indexer'


      (options[:load_path] || []).each do |path|
        $LOAD_PATH << path unless $LOAD_PATH.include? path
      end

      arg_check!

      self.indexer = initialize_indexer!

      ######
      # SAFE TO LOG to indexer.logger starting here, after indexer is set up from conf files
      # with logging config.
      #####

      indexer.logger.info("traject executing with: `#{orig_argv.join(' ')}`")

      # Okay, actual command process! All command_ methods should return true
      # on success, or false on failure.
      result =
        case options[:command]
        when "process"
          indexer.process get_input_io(self.remaining_argv)
        when "marcout"
          command_marcout! get_input_io(self.remaining_argv)
        when "commit"
          command_commit!
        else
          raise ArgumentError.new("Unrecognized traject command: #{options[:command]}")
        end

      return result
    end

    def command_commit!
      require 'open-uri'
      raise ArgumentError.new("No solr.url setting provided") if indexer.settings['solr.url'].to_s.empty?

      url = "#{indexer.settings['solr.url']}/update?commit=true"
      indexer.logger.info("Sending commit to: #{url}")
      indexer.logger.info(  open(url).read )

      return true
    end

    def command_marcout!(io)
      require 'marc'

      output_type = indexer.settings["marcout.type"].to_s
      output_type = "binary" if output_type.empty?

      output_arg      = unless indexer.settings["output_file"].to_s.empty?
        indexer.settings["output_file"]
      else
        $stdout
      end

      case output_type
      when "binary"
        writer = MARC::Writer.new(output_arg)

        allow_oversized = indexer.settings["marcout.allow_oversized"]
        if allow_oversized
          allow_oversized = (allow_oversized.to_s == "true") 
          writer.allow_oversized = allow_oversized
        end
      when "xml"
        writer = MARC::XMLWriter.new(output_arg)
      when "human"
        writer = output_arg.kind_of?(String) ? File.open(output_arg, "w:binary") : output_arg
      else
        raise ArgumentError.new("traject marcout unrecognized marcout.type: #{output_type}")
      end

      reader      = indexer.reader!(io)

      reader.each do |record|
        writer.write record
      end

      writer.close

      return true
    end

    def get_input_io(argv)
      # ARGF might be perfect for this, but problems with it include:
      # * jruby is broken, no way to set it's encoding, leads to encoding errors reading non-ascii
      #   https://github.com/jruby/jruby/issues/891
      # * It's apparently not enough like an IO object for at least one of the ruby-marc XML
      #   readers:
      #   NoMethodError: undefined method `to_inputstream' for ARGF:Object
      #      init at /Users/jrochkind/.gem/jruby/1.9.3/gems/marc-0.5.1/lib/marc/xml_parsers.rb:369
      #
      # * It INSISTS on reading from ARGFV, making it hard to test, or use when you want to give
      #   it a list of files on something other than ARGV.
      #
      # So for now we do just one file, or stdin if none given. Sorry!
      if argv.length > 1
        self.console.puts "Sorry, traject can only handle one input file at a time right now. `#{argv}` Exiting..."
        exit 1
      end
      if argv.length == 0
        indexer.logger.info "Reading from STDIN..."
        io = $stdin
      else
        indexer.logger.info "Reading from #{argv.first}"
        io = File.open(argv.first, 'r')
      end
      return io
    end

    def load_configuration_files!(my_indexer, conf_files)
      conf_files.each do |conf_path|
        begin
          file_io = File.open(conf_path)
        rescue Errno::ENOENT => e
          self.console.puts "Could not find configuration file '#{conf_path}', exiting..."
          exit 2
        end

        begin
          my_indexer.instance_eval(file_io.read, conf_path)
        rescue Exception => e
          if (conf_trace = e.backtrace.find {|l| l.start_with? conf_path}) &&
             (conf_trace =~ /\A.*\:(\d+)\:in/)
            line_number = $1
          end

          self.console.puts "Error processing configuration file '#{conf_path}' at line #{line_number}"
          self.console.puts "  #{e.class}: #{e.message}"
          if e.backtrace.first =~ /\A(.*)\:in/
            self.console.puts "  from #{$1}"
          end
          exit 3
        end
      end
    end

    def arg_check!
      if options[:command] == "process" && (options[:conf].nil? || options[:conf].length == 0)
        self.console.puts "Error: Missing required configuration file"
        self.console.puts "Exiting..."
        self.console.puts
        self.console.puts self.slop.help
        exit 2
      end
    end

    # requires bundler/setup, optionally first setting ENV["BUNDLE_GEMFILE"]
    # to tell bundler to use a specific gemfile. Gemfile arg can be relative
    # to current working directory.
    def require_bundler_setup(gemfile=nil)
      if gemfile
        # tell bundler what gemfile to use
        gem_path = File.expand_path( gemfile )
        # bundler not good at error reporting, we check ourselves
        unless File.exists? gem_path
          self.console.puts "Gemfile `#{gemfile}` does not exist, exiting..."
          self.console.puts
          self.console.puts slop.help
          exit 2
        end
        ENV["BUNDLE_GEMFILE"] = gem_path
      end
      require 'bundler/setup'
    end

    def assemble_settings_hash(options)
      settings = {}

      # `-s key=value` command line
      (options[:setting] || []).each do |setting_pair|
        if setting_pair =~ /\A([^=]+)\=(.*)\Z/
          key, value = $1, $2
          settings[key] = value
        else
          self.console.puts "Unrecognized setting argument '#{setting_pair}':"
          self.console.puts "Should be of format -s key=value"
          exit 3
        end
      end

      # other command line shortcuts for settings
      if options[:debug]
        settings["log.level"] = "debug"
      end
      if options[:writer]
        settings["writer_class_name"] = options[:writer]
      end
      if options[:reader]
        settings["reader_class_name"] = options[:reader]
      end
      if options[:solr]
        settings["solr.url"] = options[:solr]
      end
      if options[:j]
        settings["writer_class_name"] = "JsonWriter"
        settings["json_writer.pretty_print"] = "true"
      end
      if options[:marc_type]
        settings["marc_source.type"] = options[:marc_type]
      end
      if options[:output_file]
        settings["output_file"] = options[:output_file]
      end

      return settings
    end


    def create_slop!
      return Slop.new(:strict => true) do
        banner "traject [options] -c configuration.rb [-c config2.rb] file.mrc"

        on 'v', 'version', "print version information to stderr"
        on 'd', 'debug', "Include debug log, -s log.level=debug"
        on 'h', 'help', "print usage information to stderr"
        on 'c', 'conf', 'configuration file path (repeatable)', :argument => true, :as => Array
        on :s, :setting, "settings: `-s key=value` (repeatable)", :argument => true, :as => Array
        on :r, :reader, "Set reader class, shortcut for -s reader_class_name=", :argument => true
        on :o, "output_file", "output file for Writer classes that write to files", :argument => true
        on :w, :writer, "Set writer class, shortcut for -s writer_class_name=", :argument => true
        on :u, :solr, "Set solr url, shortcut for -s solr.url=", :argument => true
        on :j, "output as pretty printed json, shortcut for -s writer_class_name=JsonWriter -s json_writer.pretty_print=true"
        on :t, :marc_type, "xml, json or binary. shortcut for -s marc_source.type=", :argument => true
        on :I, "load_path", "append paths to ruby $LOAD_PATH", :argument => true, :as => Array, :delimiter => ":"
        on :G, "Gemfile", "run with bundler and optionally specified Gemfile", :argument => :optional, :default => ""

        on :x, "command", "alternate traject command: process (default); marcout", :argument => true, :default => "process"
      end
    end

    def initialize_indexer!
      indexer = Traject::Indexer.new self.assemble_settings_hash(self.options)
      load_configuration_files!(indexer, options[:conf])

      return indexer
    end

    def parse_options(argv)

      begin
        self.slop.parse!(argv)
      rescue Slop::Error => e
        self.console.puts "Error: #{e.message}"
        self.console.puts "Exiting..."
        self.console.puts
        self.console.puts slop.help
        exit 1
      end

      return self.slop.to_hash
    end


  end
end