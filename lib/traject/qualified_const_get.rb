# From http://redcorundum.blogspot.com/2006/05/kernelqualifiedconstget.html
# Adapted into a module, rather than monkey patching it into Kernel
#
# Method to take a string constant name, including :: qualifications, and
# look up the actual constant. Looks up relative to current file.
# Respects leading ::. Etc.
#
#     class Something
#       include Traject::QualifiedConstGet
#
#       def foo
#         #...
#         klass = qualified_const_get("Foo::Bar")
#         #...
#       end
#     end
module Traject::QualifiedConstGet


  def qualified_const_get(str)
    path = str.to_s.split('::')
    from_root = path[0].empty?
    if from_root
      from_root = []
      path = path[1..-1]
    else
      start_ns = ((Class === self)||(Module === self)) ? self : self.class
      from_root = start_ns.to_s.split('::')
    end
    until from_root.empty?
      begin
        return (from_root+path).inject(Object) { |ns,name| ns.const_get(name) }
      rescue NameError
        from_root.delete_at(-1)
      end
    end
    path.inject(Object) { |ns,name| ns.const_get(name) }
  end

end
