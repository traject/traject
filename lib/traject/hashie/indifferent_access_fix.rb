require 'hashie'

module Traject
  module Hashie
    # Backporting fix from https://github.com/intridea/hashie/commit/a82c594710e1bc9460d3de4d2989cb700f4c3c7f
    # into Hashie.
    #
    # This makes merge(ordinary_hash) on a Hash that has IndifferentAccess included work, without
    # raising. Which we needed.
    #
    # The fix was released in Hashie 3.6.0 (https://github.com/hashie/hashie/pull/436), so this
    # patch is only applied to older versions. Hashie 6 renamed the private helper this patch
    # relied on, so it must not be applied there.
    #
    # See also https://github.com/intridea/hashie/issues/451
    module IndifferentAccessFix
      def merge(*args)
        result = super
        ::Hashie::Extensions::IndifferentAccess.inject!(result) if hash_lacking_indifference?(result)
        result.convert!
      end
    end
  end
end
if Gem::Version.new(Hashie::VERSION) < Gem::Version.new('3.6.0')
  Hashie::Extensions::IndifferentAccess.include(Traject::Hashie::IndifferentAccessFix)
end

