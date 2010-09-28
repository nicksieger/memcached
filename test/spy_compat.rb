require 'spymemcached'

class Spymemcached::ClientCompat < Spymemcached
  def set(*args)
    super(*args[0..2])
  end

  def get(*args)
    super(args.first)
  end

  def get_multi(*args)
    multiget(*args.first)
  end

  def append(*args)
    super
  end

  def prepend(*args)
    super
  end

  def delete(key)
    del(key)
  end
end
