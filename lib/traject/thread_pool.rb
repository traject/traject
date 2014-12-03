module Traject
  if defined? JRUBY_VERSION
    require 'traject/jruby_thread_pool'
    class ThreadPool < JRubyThreadPool; end
  else
    require 'traject/all_ruby_thread_pool'
    class ThreadPool < AllRubyThreadPool;end
  end

end
