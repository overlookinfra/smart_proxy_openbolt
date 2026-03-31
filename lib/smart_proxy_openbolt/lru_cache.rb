module Proxy::OpenBolt
  # Thread-safe, size-bounded cache that evicts the least recently used
  # entry when full. Built on Ruby's insertion-ordered Hash.
  # Implemented here rather than pulling in a gem to avoid adding
  # packaging dependencies for something this straightforward.
  class LruCache
    def initialize(max_size)
      raise ArgumentError, 'max_size must be at least 1' if max_size < 1
      @max_size = max_size
      @hash = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize do
        return nil unless @hash.key?(key)
        # Move to end (most recently used)
        value = @hash.delete(key)
        @hash[key] = value
      end
    end

    def put(key, value)
      @mutex.synchronize do
        @hash.delete(key) if @hash.key?(key)
        @hash[key] = value
        @hash.shift if @hash.size > @max_size
      end
    end

    def delete(key)
      @mutex.synchronize { @hash.delete(key) }
    end

    def key?(key)
      @mutex.synchronize { @hash.key?(key) }
    end

    def size
      @mutex.synchronize { @hash.size }
    end
  end
end
