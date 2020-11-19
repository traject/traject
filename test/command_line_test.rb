# we mostly unit test with a Traject::Indexer itself and lower-level, but
# we need at least some basic top-level integration actually command line tests,
# this is a start, we can add more.

require 'test_helper'
require 'byebug'

describe "Shell out to command line" do
  # just encapsuluate using the minitest capture helper, but also
  # getting and returning exit code
  #
  #     out, err, result = execute_with_args("-c configuration")
  def execute_with_args(args)
    out, err = capture_subprocess_io do
      system("./bin/traject #{args}")
    end

    return out, err, $?
  end


  it "can dispaly version" do
    out, err, result = execute_with_args("-v")
    assert_equal err, "traject version #{Traject::VERSION}\n"
    assert result.success?
  end

  it "can display help text" do
    out, err, result = execute_with_args("-h")

    assert err.start_with?("traject [options] -c configuration.rb [-c config2.rb] file.mrc")
    assert result.success?
  end
end

