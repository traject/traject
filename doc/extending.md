# Extending With Your Own Code

Beyond very simple logic, you'll want to write your own ruby code,
organize it in files other than traject config files, but then
use it in traject config files.

You might want to have code local to your traject project; or you
might want to use ruby gems to share code between projects and developers. 
A given project may use both of these techniques.

Here are some suggestions for how to do this, along with mention
of a couple traject features meant to make it easier.

## Expert Summary

* Load Path options:
  * Traject `-I` argument command line can be used to list directories to
  add to the load path, similar to the `ruby -I` argument. You
  can then 'require' local project files from the load path.
  * Modify the ruby `$LOAD_PATH` manually at the top of a traject config file you are loading. 
  * NOTE: translation map files in a "./translation_maps" subdir on the load path will be available for to traject.
* You can use Bundler with traject simply by creating a Gemfile with `bundler init`,
  and then running command line with `bundle exec traject` or 
  even `BUNDLE_GEMFILE=path/to/Gemfile bundle exec traject`

## Custom code local to your project

You might want local translation maps, or local ruby
code. Here's a standard recommended way you might lay out
this extra code in the file system, using a 'lib'
directory kept next to your traject config files:

~~~
- my_traject/
  * config_file.rb
  - lib/
    * my_macros.rb
    * my_utility.rb
    - translation_maps/
      * my_map.yaml
~~~


The `my_macros.rb` file might contain a simple [macro](./macros.md)
in a module called `MyMacros`.

The `my_utility.rb` file might contain, say, a module of utility
methods, `MyUtility.some_utility`, etc.

To refer to ruby code from another file, we use the standard
ruby `require` statement to bring in the files:

~~~ruby
# config_file.rb

require 'my_macros'
require 'my_utility'

# Now that MyMacros is available, extend it into the indexer,
# and use it:

extend MyMacros

to_field "title", my_some_macro

# And likewise, we can use our utility methods:

to_field "title" do |record, accumulator, context|
  accumulator << MyUtility.some_utility(record)
end
~~~

**But wait!** This won't work yet. Becuase ruby won't be
able to find the file in `requires 'my_macros'`. To fix
that, we want to add our local `lib` directory to the
ruby `$LOAD_PATH`, a standard ruby feature.

Traject provides a way for you to add to the load path
from the traject command line, the `-I` flag:

    traject -I ./lib -c ./config_file.rb ...

Or, you can hard-code a `$LOAD_PATH` change directly in your
config file. You'll have to use some weird looking
ruby code to create a file path relative to the current
file (the config_file.rb), and then make sure it's
an absolute path. (Should we add a traject utility
method for this?)

~~~ruby
# at top of config_file.rb...

$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), './lib'))
~~~

That's pretty much it!

What about that translation map? The `$LOAD_PATH` modification
took care of that too, the Traject::TranslationMap will look
up translation map definition files 
in a `./translation_maps` subdir on the load path, as in `./lib/translation_maps` in this case. 


## Using gems in your traject project

If there is certain logic that is common between (traject or other)
projects, it makes sense to put it in a ruby gem.

We won't go into detail about creating ruby gems, but we
do recomend you use the `bundle gem my_gem_name` command to create
a skeleton of your gem
([one tutorial here](http://railscasts.com/episodes/245-new-gem-with-bundler?view=asciicast)).
This will also make available rake commands to install your gem locally
(`rake install`), or release it to the rubygems server (`rake release`).

There are two main methods to use a gem in your traject project: with straight rubygems, or with bundler.

### without bundler (straight rubygems):

Without bundler may be simpler, at least at first. Simply `gem install some_gem` from the command line, and now you can `require` that gem in your traject
config file, and use what it provides:

~~~ruby
#some_traject_config.rb

require 'some_gem'

SomeGem.whatever!
~~~

A gem can provide traject translation map definitions in a `lib/translation_maps` sub-directory, and traject will be able to find those translation maps when the gem is loaded (because gems' `./lib` directories are by default added to the ruby load path).

### with bundler:

If you move your traject project to another system,
where you haven't yet installed the `some_gem`, then running
traject with the above config file will, of course, fail. Or if you
move your traject project to another system with a slightly
different version of `some_gem`, your traject indexing could
behave differently in confusing ways. As the number of gems
you are using increases, managing the gems and gem versions gets increasingly
confusing.

[bundler](http://bundler.io/) was invented to make this kind of dependency management in ruby more straightforward and reliable. We recommend you consider using bundler, especially for traject installations where traject will
be run via automated batch jobs on production servers.

Bundler's behavior is based on a `Gemfile` that lists your
project dependencies. You can create a starter skeleton
by running `bundler init`, probably in the directory
right next to your traject config files.

Then specify what gems your traject project will use,
possibly with version restrictions, in the [Gemfile](http://bundler.io/v1.3/gemfile.html)

Be sure to include `gem 'traject'` in the Gemfile.

Run `bundle install` from the directory with the Gemfile, on any system
at any time, to make sure specified gems are installed.  (The bundler gem must be already installed on the system.)

**Run traject** with `bundle exec` to have bundler set up the traject environment from your Gemfile. You can `cd` into the directory containing the Gemfile, so bundler can find it: 

    $ cd /some/where
    $ bundle exec traject -c some_traject_config.rb ...
    
Or you can use the BUNDLE_GEMFILE environment variable to tell bundler where
to find the Gemfile, and run from any directory at all:

    $ BUNDLE_GEMFILE=/path/to/Gemfile bundle exec traject -c /path/to/some_config.rb ...

Bundler will make sure the specified versions of all gems are used by
traject, and also make sure no gems except those specified in the gemfile
are available to the program, for a reliable reproducible environment. 

You still need to `require` the gem in your traject config file;
then just refer to what it provides in your config code as usual. 

You should check both the `Gemfile` and the `Gemfile.lock`
that bundler creates into your source control repo. The
`Gemfile.lock` specifies _exactly_ what versions of
gem dependencies are currently being used, so you can get the exact
same dependency environment on different servers.

See the [bundler documentation](http://bundler.io/#getting-started), or google, for more information. 
