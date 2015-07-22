require_relative 'spec_helper'

class FakeCache
  def initialize
    @store = {}
  end

  def fetch key, opts={}, &block
    value = @store[key]

    if !@store.has_key?(key) && block
      value = block.call

      @store[key] = value
    end

    value
  end
end

describe Jblazer do
  def make_template context=nil
    json = Jblazer::Template.new context
    json.cache_backend = FakeCache.new

    yield json

    json
  end

  it 'should have a context' do
    context = Object.new

    make_template context do |json|
      expect(json.context).to equal(context)
    end
  end

  it 'should compile an empty document' do
    json = make_template {|json| nil }

    expect(json.to_s).to eql ''
  end

  it 'should compile an array of values' do
    template = make_template do |json|
      json.array! [1, '2', :'3']
    end

    expect(template.to_s).to eql '[1,"2","3"]'
  end

  it 'should compile an empty array' do
    template = make_template do |json|
      json.array! []
    end

    expect(template.to_s).to eql '[]'
  end

  it 'should compile an object' do
    template = make_template do |json|
      json.a 'b'
      json.c 1
    end

    expect(template.to_s).to eql '{"a":"b","c":1}'
  end

  it 'should compile an array of arrays' do
    items = [:foo, 'bar', 123]

    template = make_template do |json|
      json.array! items do |item|
        json.array! [item]
      end
    end

    expect(template.to_s).to eql '[["foo"],["bar"],[123]]'
  end

  it 'should compile an array of objects' do
    items = [
      {:a => 1},
      {:b => 2}
    ]

    template = make_template do |json|
      json.items items do |item|
        item.each do |key, value|
          json.send key, value
        end
      end
    end

    expect(template.to_s).to eql '{"items":[{"a":1},{"b":2}]}'
  end

  AnObject = Struct.new :a, :b

  it 'should extract some values' do
    object = AnObject.new 1, 2

    template = make_template do |json|
      json.extract! object, :a, :b
    end

    expect(template.to_s).to eql '{"a":1,"b":2}'
  end

  it 'should handle a #call' do
    object = AnObject.new 3, 4

    template = make_template do |json|
      json.(object, :a, :b)
    end

    expect(template.to_s).to eql '{"a":3,"b":4}'
  end

  it 'should define a value with a block' do
    template = make_template do |json|
      json.a do
        json.b 'c'
      end
    end

    expect(template.to_s).to eql '{"a":{"b":"c"}}'
  end

  describe 'caching' do
    it 'should cache array members' do
      array = [:a, :b]

      cache_spy = spy('cache')
      cache = FakeCache.new

      render = Proc.new do
        json = Jblazer::Template.new nil
        json.cache_backend = cache

        index = 0

        json.array! array do |item|
          key = index.to_s

          json.cache!(key) do
            cache_spy.miss

            json.index index
            json.value item
          end

          index += 1
        end

        json.to_s
      end

      json = '[{"index":0,"value":"a"},{"index":1,"value":"b"}]'

      expect(cache_spy).not_to have_received(:miss)

      # Check that the initial render is correct and misses the cache
      expect(render.call).to eql json
      expect(cache_spy).to have_received(:miss).twice

      # Check that the second render hits the cache (ie. no change in
      # call count)
      expect(render.call).to eql json
      expect(cache_spy).to have_received(:miss).twice
    end
  end
end
