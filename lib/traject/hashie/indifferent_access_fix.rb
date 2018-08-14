require 'hashie'

module Traject
  module Hashie
    # Backporting fix from https://github.com/intridea/hashie/commit/a82c594710e1bc9460d3de4d2989cb700f4c3c7f
    # into Hashie.
    #
    # This makes merge(ordinary_hash) on a Hash that has IndifferentAccess included work, without
    # raising. Which we needed.
    #
    # As of this writing that fix is not available in a Hashie release, if it becomes so
    # later than this monkey-patch may no longer be required, we can just depend on fixed version.
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
Hashie::Extensions::IndifferentAccess.include(Traject::Hashie::IndifferentAccessFix)

