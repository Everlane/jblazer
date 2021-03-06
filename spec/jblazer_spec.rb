require_relative 'spec_helper'
require 'active_support/json/encoding'

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

Jblazer::Template.cache_backend = FakeCache.new

describe Jblazer do
  def make_template context=nil
    json = Jblazer::Template.new context

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

  it 'should directly set an array in another array' do
    first  = [1, 4]
    second = [2, 5]
    third  = [3, 6]

    template = make_template do |json|
      json.array! first do |value|
        json.x value
        json.y do
          json.array! [second.shift]
        end
        json.z third.shift
      end
    end

    expect(template.to_s).to eql '[{"x":1,"y":[2],"z":3},{"x":4,"y":[5],"z":6}]'
  end

  it 'should error on second definitions in single-definition contexts' do
    # Test #method_missing
    expect {
      make_template do |json|
        json.a do
          json.array! ['b']
          json.c 'd'
        end
      end
    }.to raise_error /second definition/

    # Test #array!
    expect {
      make_template do |json|
        json.a do
          json.array! ['b']
          json.array! ['c']
        end
      end
    }.to raise_error /second definition/
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

  it 'should extract from an object' do
    object = AnObject.new 1, 2

    template = make_template do |json|
      json.extract! object, :a, :b
    end

    expect(template.to_s).to eql '{"a":1,"b":2}'
  end

  it 'should extract from a hash' do
    hash = {:a => 1, :b => 2}

    template = make_template do |json|
      json.extract! hash, :a, :b
    end

    expect(template.to_s).to eql '{"a":1,"b":2}'
  end

  it 'should receive a #call' do
    object = AnObject.new 3, 4

    template = make_template do |json|
      json.(object, :a, :b)
    end

    expect(template.to_s).to eql '{"a":3,"b":4}'
  end

  it 'should generate null' do
    template = make_template do |json|
      json.a do
        json.b '1'
        json.c do
          json.null!
        end
      end
    end

    expect(template.to_s).to eql '{"a":{"b":"1","c":null}}'
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
