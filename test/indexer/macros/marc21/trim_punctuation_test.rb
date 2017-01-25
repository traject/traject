# encoding: UTF-8
require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21'


include Traject::Macros::Marc21

describe "trim_punctuation" do

  # TODO: test coverage for trim_punctuation
  # trim_punctuation isn't super-complicated code, and yet we've found a few bugs
  # in it already. Needs more test coveragel
  it "Works as expected" do
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("one two three")

    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("one two three,")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("one two three/")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("one two three;")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("one two three:")
    assert_equal "one two three .", Traject::Macros::Marc21.trim_punctuation("one two three .")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("one two three.")
    assert_equal "one two three...", Traject::Macros::Marc21.trim_punctuation("one two three...")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation(" one two three.")

    assert_equal "one two [three]", Traject::Macros::Marc21.trim_punctuation("one two [three]")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("one two three]")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("[one two three")
    assert_equal "one two three", Traject::Macros::Marc21.trim_punctuation("[one two three]")

    # This one was a bug before
    assert_equal "Feminism and art", Traject::Macros::Marc21.trim_punctuation("Feminism and art.")
    assert_equal "Le réve", Traject::Macros::Marc21.trim_punctuation("Le réve.")

    # This one was a bug on the bug
    assert_equal "Bill Dueber, Jr.", Traject::Macros::Marc21.trim_punctuation("Bill Dueber, Jr.")
  end
end
