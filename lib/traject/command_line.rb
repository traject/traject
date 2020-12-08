require 'slop'
require 'traject'
require 'traject/indexer'

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
    # orig_argv is original one passed in, remaining_argv is after destructive
    # processing by slop, still has file args in it etc.
    attr_accessor :orig_argv, :remaining_argv
    attr_accessor :slop, :options
    attr_accessor :indexer
    attr_accessor :console

    @@indexer_class_shortcuts = {
      "basic" => "Traject::Indexer",
      "marc"  => "Traject::Indexer::MarcIndexer",
      "xml"   => "Traject::Indexer::NokogiriIndexer"
    }

    def initialize(argv=ARGV)
      self.console = $stderr

      self.orig_argv      = argv.dup

      self.slop    = create_slop!(argv)
      self.options = self.slop
      self.remaining_argv = self.slop.arguments
    end

    # Returns true on success or false on failure; may also raise exceptions;
    # may also exit program directly itself (yeah, could use some normalization)
    def execute
      if options[:version]
        self.console.puts "traject version #{Traject::VERSION}"
        return true
      end
      if options[:help]
        self.console.puts slop.to_s
        return true
      end


      (options[:load_path] || []).each do |path|
        $LOAD_PATH << path unless $LOAD_PATH.include? path
      end

      arg_check!

      self.indexer = initialize_indexer!

      ######
      # SAFE TO LOG to indexer.logger starting here, after indexer is set up from conf files
      # with logging config.
      #####

      indexer.logger.info("traject (#{Traject::VERSION}) executing with: `#{orig_argv.join(' ')}`")

      # Okay, actual command process! All command_ methods should return true
      # on success, or false on failure.
      result =
        case options[:command]
        when "process"
          (io, filename) = get_input_io(self.remaining_argv)
          indexer.settings['command_line.filename'] = filename if filename
          indexer.process(io)
        when "marcout"
           (io, filename) = get_input_io(self.remaining_argv)
          indexer.settings['command_line.filename'] = filename if filename
          command_marcout!(io)
        when "commit"
          command_commit!
        else
          raise ArgumentError.new("Unrecognized traject command: #{options[:command]}")
        end

      return result
    rescue Exception => e
      # Try to log unexpected exceptions if possible
      indexer && indexer.logger && indexer.logger.fatal("Traject::CommandLine: Unexpected exception, terminating execution: #{Traject::Util.exception_to_log_message(e)}") rescue nil
      raise e
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

      indexer.logger.info("   marcout writing type:#{output_type} to file:#{output_arg}")

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

    # @return (Array<#read>, String)
    def get_input_io(argv)
      filename = nil
      io_arr = nil
      if options[:stdin]
        indexer.logger.info("Reading from standard input")
        io_arr = [$stdin]
      elsif argv.length == 0
        io_arr = [File.open(File::NULL, 'r')]
        indexer.logger.info("Warning, no file input given. Use command-line argument '--stdin' to use standard input ")
      else
        io_arr = argv.collect { |path| File.open(path, 'r') }
        filename = argv.join(",")
        indexer.logger.info "Reading from #{filename}"
      end

      return io_arr, filename
    end

    def load_configuration_files!(my_indexer, conf_files)
      conf_files.each do |conf_path|
        begin
          my_indexer.load_config_file(conf_path)
        rescue Errno::ENOENT, Errno::EACCES => e
          self.console.puts "Could not read configuration file '#{conf_path}', exiting..."
          exit 2
        rescue Traject::Indexer::ConfigLoadError => e
          self.console.puts "\n"
          self.console.puts e.message
          self.console.puts e.config_file_backtrace
          self.console.puts "\n"
          self.console.puts "Exiting..."
          exit 3
        end
      end
    end

    def arg_check!
      if options[:command] == "process" && (!options[:conf] || options[:conf].length == 0)
        self.console.puts "Error: Missing required configuration file"
        self.console.puts "Exiting..."
        self.console.puts
        self.console.puts self.slop.to_s
        exit 2
      end
    end


    def assemble_settings_hash(options)
      settings = {}

      # `-s key=value` command line
      (options[:setting] || []).each do |setting_pair|
        if m  = /\A([^=]+)\=(.*)\Z/.match(setting_pair)
          key, value = m[1], m[2]
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
      if options[:'debug-mode']
        require 'traject/debug_writer'
        settings["writer_class_name"] = "Traject::DebugWriter"
        settings["log.level"] = "debug"
        settings["processing_thread_pool"] = 0
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
      if options[:marc_type]
        settings["marc_source.type"] = options[:marc_type]
      end
      if options[:output_file]
        settings["output_file"] = options[:output_file]
      end

      return settings
    end


    def create_slop!(argv)
      options = Slop::Options.new do |o|
        o.banner = "traject [options] -c configuration.rb [-c config2.rb] file.mrc"

        o.on '-v', '--version', "print version information to stderr"
        o.on '-d', '--debug', "Include debug log, -s log.level=debug"
        o.on '-h', '--help', "print usage information to stderr"
        o.array '-c', '--conf', 'configuration file path (repeatable)', :delimiter => nil
        o.string "-i", '--indexer', "Traject indexer class name or shortcut", :default => "marc"
        o.array "-s", "--setting", "settings: `-s key=value` (repeatable)", :delimiter => nil
        o.string "-r", "--reader", "Set reader class, shortcut for -s reader_class_name="
        o.string "-o", "--output_file", "output file for Writer classes that write to files"
        o.string "-w", "--writer", "Set writer class, shortcut for -s writer_class_name="
        o.string "-u", "--solr", "Set solr url, shortcut for -s solr.url="
        o.string "-t", "--marc_type", "xml, json or binary. shortcut for -s marc_source.type="
        o.array "-I", "--load_path", "append paths to ruby $LOAD_PATH", :delimiter => ":"

        o.string "-x", "--command", "alternate traject command: process (default); marcout; commit", :default => "process"

        o.on "--stdin", "read input from stdin"
        o.on "--debug-mode", "debug logging, single threaded, output human readable hashes"
      end

      options.parse(argv)
    rescue Slop::Error => e
      self.console.puts "Error: #{e.message}"
      self.console.puts "Exiting..."
      self.console.puts
      self.console.puts options.to_s
      exit 1
    end

    def initialize_indexer!
      indexer_class_name = @@indexer_class_shortcuts[options[:indexer]] || options[:indexer]
      klass = Traject::Indexer.qualified_const_get(indexer_class_name)

      indexer = klass.new self.assemble_settings_hash(self.options)
      load_configuration_files!(indexer, options[:conf])

      return indexer
    end
  end
end
