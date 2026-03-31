require 'test_helper'
require 'smart_proxy_openbolt/lru_cache'

class LruCacheTest < Test::Unit::TestCase
  def test_stores_and_retrieves_values
    cache = Proxy::OpenBolt::LruCache.new(10)
    cache.put('key', 'value')
    assert_equal 'value', cache.get('key')
  end

  def test_returns_nil_for_missing_keys
    cache = Proxy::OpenBolt::LruCache.new(10)
    assert_nil cache.get('missing')
  end

  def test_evicts_oldest_when_full
    cache = Proxy::OpenBolt::LruCache.new(3)
    cache.put('a', 1)
    cache.put('b', 2)
    cache.put('c', 3)
    cache.put('d', 4)

    assert_nil cache.get('a'), 'Oldest entry should be evicted'
    assert_equal 2, cache.get('b')
    assert_equal 4, cache.get('d')
  end

  def test_get_refreshes_entry
    cache = Proxy::OpenBolt::LruCache.new(3)
    cache.put('a', 1)
    cache.put('b', 2)
    cache.put('c', 3)

    # Access 'a' to make it most recently used
    cache.get('a')

    # 'b' is now the oldest
    cache.put('d', 4)

    assert_equal 1, cache.get('a'), 'Accessed entry should survive eviction'
    assert_nil cache.get('b'), 'Least recently used should be evicted'
  end

  def test_put_updates_existing_key
    cache = Proxy::OpenBolt::LruCache.new(3)
    cache.put('key', 'old')
    cache.put('key', 'new')

    assert_equal 'new', cache.get('key')
    assert_equal 1, cache.size
  end

  def test_delete_removes_entry
    cache = Proxy::OpenBolt::LruCache.new(10)
    cache.put('key', 'value')
    cache.delete('key')

    assert_nil cache.get('key')
    assert_equal 0, cache.size
  end

  def test_key_check
    cache = Proxy::OpenBolt::LruCache.new(10)
    cache.put('exists', true)

    assert cache.key?('exists')
    assert !cache.key?('missing')
  end

  def test_rejects_max_size_below_one
    assert_raise(ArgumentError) { Proxy::OpenBolt::LruCache.new(0) }
    assert_raise(ArgumentError) { Proxy::OpenBolt::LruCache.new(-1) }
  end
end
