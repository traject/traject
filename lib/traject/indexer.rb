require 'hashie'

class Traject::Indexer

  def initialize
    @settings = Settings.new
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

  # Enhanced with a few features from Hashie, to make it for
  # instance string/symbol indifferent
  class Settings < Hash
    include Hashie::Extensions::IndifferentAccess

    # Hashie bug Issue #100 https://github.com/intridea/hashie/pull/100
    alias_method :store, :indifferent_writer
  end
end