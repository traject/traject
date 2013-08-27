# Hints for running traject as a batch job

Maybe as a cronjob. Maybe via a batch shell script that executes
traject, and maybe even pipelines it together with other commands.

These are things you might want to do with traject. Some potential problem points
with suggested solutions, and additional hints.

## Ruby version setting

traject ordinarily needs to run under jruby. You will
ordinarily have jruby installed under a ruby version switcher -- we
highly recommend [chruby](https://github.com/postmodern/chruby) over other choices,
but other popular choices include rvm and rbenv.

Remember that traject needs to run in 1.9.x mode in jruby--
with jruby 1.7.x or later, this should be default, recommend
you use jruby 1.7.x.

Especially when running under a cron job, it can be difficult to
set things up so traject runs under jruby.

It can sometimes be useful to create a wrapper script for traject
that takes care of making sure it's running under the right ruby
version.

### for chruby

Simply run with:

    chruby-exec jruby -- traject {other arguments}

Whether specifying that directly in a crontab, or in a shell script
that needs to call traject, etc. So simple you might not need
a wrapper script, but it might still be convenient to create one. Say
you put a `jruby-traject` at `/usr/local/bin/jruby-traject`, that
looks like this:

    #!/usr/bin/env bash

    chruby-exec jruby -- traject "$@"

Now any account, in a crontab, in an interactive shell, wherever,
can just execute `jruby-traject {arguments}`, and execute traject
in a jruby environment.

### for rbenv

If running in an interactive shell that has had rbenv set up for
it, you can use rbenv's standard mechanism to say to execute
something in jruby:

    RBENV_VERSION=jruby-1.7.2 traject {args}

You do need to specify the exact version of jruby, I don't think
there's any way to say 'latest install jruby'. You could do the
same thing for any batch scripts you're writing -- just have
them set that `RBENV_VERSION` environment variable before
executing traject.

If you're running inside a cronjob, things get a bit trickier,
because rbenv isn't normally set up in the limited environment
of cron tasks. One way to deal with this is to have your
cronjob explicitly execute in a bash login shell, that
will then have rbenv set up so long as it's running
under an account with rbenv set up properly!

    # in a cronfile
    # 10 * * * * /bin/bash -l -c 'RBENV_VERSION=jruby-1.7.2 traject {args}'

(Better way? Doc pull requests welcome.)


~~~bash
#!/usr/bin/env bash

/bin/bash -lc RBENV_VERSION=jruby-1.7.2 traject "$@"
~~~

The `bash -lc` is needed to load rbenv, when calling from a cronjob,
and then we set the `RBENV_VERSION` env variable to tell it what to do.

Now you can have a crontab or batch script call `jruby-traject {whatever args}`, and execute
traject in a jruby environment. If you'll be executing it from an interactive shell,
maybe you don't need the seperate bash invocation.

(Better way with rbenv? Doc pull requests welcome.)


### for rvm

See rvm's [own docs on use with cron](http://rvm.io/integration/cron), it gets a bit confusing.
But here's one way, using a wrapper script. It does require you to
identify and hard-code in where your rvm is installed, and exactly which
version of jruby you want to execute with (will have to be updated if you upgrade
jruby). (Is there a better way? Doc pull requests welcome! rvm confuses me!)

Make a file at `/usr/local/bin/jruby-traject` that looks like this:


~~~bash
#!/usr/bin/env bash

# load rvm ruby
source /home/MY_ACCT/.rvm/environments/jruby-1.7.3

traject "$@"
~~~

You have to use your actual account rvm is installed in for MY_ACCT.
Or, if you have a global install of rvm instead of a user-account one,
it might be at `/usr/local/rvm/environments`... instead.

Now any account, in a crontab, in an interactive shell, wherever,
can just execute `jruby-traject {arguments}`, and execute traject
in a jruby environment.

## Exit codes

Traject tries to always return a well-behaved unix exit code -- 0 for success,
non-0 for error.

You should be able to rely on this in your batch bash scripts, if you want to abort
further processing if traject failed for some reason, you can check traject's
exit code.

If an uncaught exception happens, traject will return non-0.

There are some kinds of errors which prevent traject from indexing
one or more records, but traject may still continue processing
the other records. If any records have been skipped in this way,
traject will _also_ return a non-0 failure exit code. (Is this good?
Does it need to be configurable?)

In these cases, information about errors that led to skipped records should
be output as ERROR level in the logs.

## Logs and Error Reporting

By default, traject outputs all logging to stderr.  This is often just what
you want for a batch or automated process, where there might be some wrapper
script which captures stderr and puts it where you want it.

However, it's easy enough to tell traject to log somewhere else. Either on
the command-line:

   traject -s log.file=/some/other/file/log {other args}

Or in a traject configuration file, setting the `log.file` configuration setting.

You can also seperately have a duplicate log file created with ONLY log messages of
level ERROR and higher (meaning ERROR and FATAL), with the `log.error_file` setting.
Then, if there's any lines in this error log file at all, you know something bad
happened, maybe your batch process needs to notify someone, or abort further
steps in the batch process.

    traject -s log.file=/var/log/traject.log -s log.error_file=/var/log/traject_error.log {more args}

The error lines will be in the main log file, and also duplicated in the error
log file.

Traject uses the [yell](https://github.com/rudionrails/yell) gem for logging.
You can configure the logger directly to implement whatever crazy logging rules you might
want, so long as yell supports them. But yell is pretty flexible.

Recall that traject config files are just ruby, executed in the context
of a Traject::Indexer. You can set the Indexer's `logger` to a yell logger
object you configure yourself however you like:

~~~ruby
  # inside a traject configuration file

  logger = Yell.new do |l|
    l.level = 'gte.info' # will only pass :info and above to the adapters

    l.adapter :datefile, 'production.log', level: 'lte.warn' # anything lower or equal to :warn
    l.adapter :datefile, 'error.log', level: 'gte.error' # anything greater or equal to :error
  end
~~~

See [yell](https://github.com/rudionrails/yell)  docs for more, you can
do whatever you can make yell, just write ruby.