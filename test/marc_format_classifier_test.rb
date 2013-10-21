require 'test_helper'

require 'traject/macros/marc_format_classifier'

MarcFormatClassifier = Traject::Macros::MarcFormatClassifier

def classifier_for(filename)
  record = MARC::Reader.new(support_file_path  filename).to_a.first
  return MarcFormatClassifier.new( record  )
end

describe "MarcFormatClassifier" do
  
  it "returns 'Print' when there's no other data" do
    assert_equal ['Print'],  MarcFormatClassifier.new( empty_record  ).formats
  end
  
  describe "genre" do
    # We don't have the patience to test every case, just a sampling
    it "says book" do
      assert_equal ["Book"], classifier_for("manufacturing_consent.marc").genre
    end
    it "says Book for a weird one" do
      assert_equal ["Book"], classifier_for("microform_online_conference.marc").genre
    end
    it "says Musical Recording" do
      assert_equal ["Musical Recording"], classifier_for("musical_cage.marc").genre
    end
    it "says Journal" do
      assert_equal ["Journal/Newspaper"], classifier_for("the_business_ren.marc").genre
    end
  end


  describe "print?" do
    it "says print when it is" do
      assert classifier_for("manufacturing_consent.marc").print?
    end
    it "does not say print for online only" do
      assert ! classifier_for("online_only.marc").print?
    end
  end

  describe "online?" do
    it "says online when it is" do
      assert classifier_for("online_only.marc").online?
      assert classifier_for("microform_online_conference.marc").online?
      assert classifier_for("manuscript_online_thesis.marc").online?
    end
    it "does not say online for a print only" do
      assert ! classifier_for("manufacturing_consent.marc").online?
    end
  end

  describe "microform?" do
    it "says microform when it is" do
      assert classifier_for("microform_online_conference.marc").microform?
    end
    it "does not say microform when it ain't" do
       assert ! classifier_for("manufacturing_consent.marc").microform?
       assert ! classifier_for("online_only.marc").microform?
    end
    it "catches microform in an 007" do
      assert classifier_for("nature.marc").microform?
    end
  end

  describe "conference?" do
    it "says conference when it is" do
      assert classifier_for("microform_online_conference.marc").proceeding?
    end
    it "does not say conference when it ain't" do
      assert ! classifier_for("manufacturing_consent.marc").proceeding?
      assert ! classifier_for("online_only.marc").proceeding?
    end
  end

  describe "thesis?" do
    it "says thesis when it is" do
      assert classifier_for("manuscript_online_thesis.marc").thesis?
    end
    it "does not say thesis when it ain't" do
      assert ! classifier_for("manufacturing_consent.marc").thesis?
      assert ! classifier_for("online_only.marc").thesis?
    end
  end

  describe "manuscript_archive?" do
    it "says manuscript when it is" do
      assert classifier_for("manuscript_online_thesis.marc").manuscript_archive?
    end
    it "does not say manuscript when it ain't" do
      assert ! classifier_for("manufacturing_consent.marc").manuscript_archive?
      assert ! classifier_for("online_only.marc").manuscript_archive?
    end
  end

end
