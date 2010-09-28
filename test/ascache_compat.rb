module ActiveSupport
  class CacheStoreClient
    def initialize(store)
      @store = store
    end

    def get(key, raw = false)
      @store.read(key, :raw => raw)
    end

    def set(key, value, expiry = 0, raw = false)
      @store.write(key, value, :expires_in => expiry, :raw => raw)
    end

    def get_multi(keys, raw = false)
      @store.read_multi(*(keys.dup << {:raw => raw}))
    end

    def delete(key)
      @store.delete(key)
    end
  end
end
