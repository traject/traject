# A Null writer that does absolutely nothing with records given to it,
# just drops em on the floor.
class Traject::NullWriter
  attr_reader :settings

  def initialize(argSettings)
  end


  def serialize(context)
    # null
  end

  def put(context)
    # null
  end

  def close
    # null
  end

end
