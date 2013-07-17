# Traject Indexing 'Macros'

Traject macros are a way of providing re-usable index mapping rules. Before we discuss how they work, we need to remind ourselves of the basic/direct Traject `to_field` indexing method. 

## Review and details of direct indexing logic

Here's the simplest possible direct Traject mapping logic, duplicating the effects of the `literal` function:

~~~ruby
to_field("title") do |record, accumulator, context|
  accumulator << "FIXED LITERAL"
end
~~~

That `do` is just ruby `block` syntax, whereby we can pass a block of ruby code as an argument to to a ruby method. We pass a block taking three arguments, labelled `record`, `accumulator`, and `context`, to the `to_field` method. 

The block is then stored by the Traject::Indexer, and called for each record indexed. When it's called, it's passed the particular record at hand for the first argument, an Array used as an 'accumulator' as the second argument, and a Traject::Indexer::Context as the third argument. 

The code in the block can add values to the accumulator array, which the Traject::Indexer then adds to the field specified by `to_field`. 

It's also worth pointing out that ruby blocks are `closures`, so they can "capture" and use values from outside the block. So this would work too:

~~~ruby
my_var = "FIXED LITERAL"
to_field("title") do |record, accumulator, context|
  accumulator << my_var
end
~~~

So that's the way to provide direct logic for mapping rules. 

## Macros

A Traject macro is a way to automatically create indexing rules via re-usable "templates". 

Traject macros are simply methods that return ruby lambda/proc objects. A ruby lambda is just another syntax for creating blocks of ruby logic that can be passed around as data. 

So, for instance, we could capture that fixed literal block in a lambda like this:

~~~ruby
always_add_black = lambda do |record, accumulator, context|
   accumulator << "BLACK"
end
~~~

Then, knowing that the `to_field` ruby method takes a block, we can use the ruby `&` operator
to convert our lambda to a block argument. This would in fact work:

~~~ruby
to_field "color", &always_add_black
~~~

However, for convenience, the `to_field` method can take a lambda directly (without having to use '&' to convert it to a block argument) as a second argument too. So this would work too:

~~~ruby
to_field "color", always_add_black
~~~

A macro is jus more step, using a method to create lambdas dynamically:  A Traject macro is just a ruby method that **returns** a lambda, a three-arg lambda like `to_field` wants. 

Here is in fact how the `literal` function is implemented:

~~~ruby
def literal(value)
  return lambda do |record, accumulator, context|
     # because a lambda is a closure, we can define it in terms
     # of the 'value' from the scope it's defined in!
     accumulator << value
  end
end
to_field("something"), literal("something")
~~~

It's really as simple as that, that's all a Traject macro is. A function that takes parameters, and based on those parameters returns a lambda; the lambda is then passed to the `to_field` indexing method, or similar methods. 

How do you make these methods available to the indexer?

Define it in a module:

~~~ruby
# in a file literal_macro.rb
module LiteralMacro
  def literal(value)
    return lambda do |record, accumulator, context|
       # because a lambda is a closure, we can define it in terms
       # of the 'value' from the scope it's defined in!
       accumulator << value
    end
  end
end
~~~

And then use ordinary ruby `require` and `extend` to add it to the current Indexer file, by simply including this
in one of your config files:

~~~
require `literal_macro.rb`
extend LiteralMacro

to_field ...
~~~

That's it.  You can use the traject command line `-I` option to set the ruby load path, so your file will be findable via `require`.  Or you can distribute it in a gem, and use straight rubygems and the `gem` command in your configuration file, or Bundler with traject command-line `-g` option. 