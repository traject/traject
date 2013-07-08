require 'hashie'

class Traject::Indexer

  def initialize
    @settings = Settings.new
    @index_steps = []
  end

  # The Indexer's settings are a hash of key/values -- not
  # nested, just one level -- of configuration settings. Keys
  # are strings.
  #
  # The settings method with no arguments returns that hash.
  #
  # With a hash and/or block argument, can be used to set
  # new key/values. Each call merges onto the existing settings
  # hash. 
  #
  #    indexer.settings("a" => "a", "b" => "b")
  #
  #    indexer.settings do
  #      store "b", "new b"
  #    end
  #
  #    indexer.settings #=> {"a" => "a", "b" => "new b"} 
  #
  # even with arguments, returns settings hash too, so can
  # be chained. 
  def settings(new_settings = nil, &block)
    @settings.merge!(new_settings) if new_settings

    @settings.instance_eval &block if block
    
    return @settings
  end

  # Used to define an indexing mapping. 
  def to_field(field_name, aLambda = nil, &block)
    @index_steps << {
      :field_name => field_name.to_s,
      :lambda => aLambda,
      :block  => block
    }
  end

  # Processes a single record, according to indexing rules
  # set up in this Indexer. Returns a hash whose values are
  # Arrays, and keys are strings. 
  def map_record(record)
    output_hash = {}

    @index_steps.each do |index_step|
      accumulator = []
      field_name  = index_step[:field_name]
      
      # Might have a lambda arg AND a block, we execute in order,
      # with same accumulator.
      [index_step[:lambda], index_step[:block]].each do |aProc|
        aProc.call(record, accumulator) if aProc
      end

      (output_hash[field_name] ||= []).concat accumulator      
    end

    return output_hash
  end


  # Enhanced with a few features from Hashie, to make it for
  # instance string/symbol indifferent
  class Settings < Hash
    include Hashie::Extensions::IndifferentAccess

    # Hashie bug Issue #100 https://github.com/intridea/hashie/pull/100
    alias_method :store, :indifferent_writer
  end
end