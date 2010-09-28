require 'dalli'

class Dalli::ClientCompat < Dalli::Client
  def set(*args)
    super(*args[0..2])
  end
  def get(*args)
    super(args.first)
  end
  def get_multi(*args)
    super(args.first)
  end
  def append(*args)
    super
  rescue Dalli::DalliError
  end
  def prepend(*args)
    super
  rescue Dalli::DalliError
  end
end
