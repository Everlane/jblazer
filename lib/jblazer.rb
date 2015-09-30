require 'active_support/proxy_object'
require 'multi_json'

module Jblazer
  class UnwindableBuffer
    def initialize
      @contents = []
    end

    def <<(item)
      @contents << item
    end

    def to_s
      @contents.map(&:strip).join ''.freeze
    end

    def last
      @contents.last
    end

    def unwind
      @contents.pop
    end
  end

  class Template < ::ActiveSupport::ProxyObject
    attr_reader :buffer, :context

    def initialize context
      @context = context
      @buffer = UnwindableBuffer.new

      # Keeps track of structures implicitly opened and closed
      @implicit_stack = []
      # If we're evaluating the first item in a potentially-implicit structure
      @is_first = true
    end

    def array! items
      check_for_single!

      @buffer << '['.freeze

      # If we're the first definition in an implicit object then
      # we'll assume we're the ONLY definition in that object.
      if @is_first && @implicit_stack.last == :object
        @implicit_stack << :single
      end

      @implicit_stack << :array

      depth      = @implicit_stack.length
      last_index = items.count - 1

      items.each_with_index do |item, index|
        @is_first = true

        if ::Kernel.block_given?
          yield item
        else
          @buffer << to_json(item)
        end

        # Close whatever was opened by the item
        implicitly_close if @implicit_stack.length > depth

        @buffer << ','.freeze unless index == last_index
      end

      @is_first = false
      @buffer << ']'.freeze

      top = @implicit_stack.pop
      unless top == :array
        raise "Unexpected top of implicit stack: #{top.to_s}"
      end
    end

    def partial! name, opts
      check_for_single!

      raise ':collection not supported yet' if opts[:collection]
      raise ':as not supported yet'         if opts[:as]

      locals = opts.delete(:locals) || {}

      locals.merge! opts

      ret = @context.render :partial => name, :locals => locals

      @buffer << ret
    end

    def extract! obj, *keys
      check_for_single!
      implicitly_open :object

      is_hash = obj.kind_of? ::Hash

      keys.each do |key|
        value = is_hash ? obj[key] : obj.send(key)
        @buffer << to_json(key)
        @buffer << ':'.freeze
        @buffer << to_json(value)
        @buffer << ','.freeze
      end
    end

    def compute_cache_key key
      key
    end

    def cache! key, opts={}, &block
      cache_key = compute_cache_key key

      depth = @implicit_stack.length

      value = Template.cache_backend.fetch(cache_key, opts) do
        # Create a temporary buffer for the cached bit
        @original_buffer = @buffer
        @buffer = UnwindableBuffer.new

        @is_first = true

        block.call

        implicitly_close if @implicit_stack.length > depth

        # Restore the original buffer and return the contents of the
        # temporary one
        contents = @buffer.to_s
        @buffer = @original_buffer

        contents
      end

      @buffer << value
    end

    def call *args
      raise ArgumentError, "expects at least 2 arguments" if args.length < 2

      check_for_single!
      implicitly_open :object

      receiver, *properties = args

      extract! receiver, *properties
    end

    def null!
      if !@is_first
        raise RuntimeError, "null! must be the first and only call"
      end

      @buffer << 'null'.freeze

      @is_first = false
    end

    def method_missing name, *args
      block_given = ::Kernel.block_given?
      count       = args.count

      check_for_single! if count > 0
      implicitly_open :object

      @buffer << to_json(name)
      @buffer << ':'.freeze

      if count > 1
        raise "Too many arguments (max is 1, got #{args.length})"

      elsif count == 1 && block_given
        given_block = ::Proc.new

        array! args.first, &given_block

      elsif count == 1
        @buffer << to_json(args.first)

      elsif block_given
        implicitly_open :object

        @is_first = true

        yield self

        implicitly_close

      else
        raise "Missing value argument for '#{name}'"
      end

      @buffer << ','.freeze
    end

    # ProxyObject doesn't provide #send (since it subclasses BasicObject, so
    # we need to fudge our own implementation).
    def send key, value
      method_missing key, value
    end

    def to_s
      implicitly_close if @implicit_stack.length > 0

      @buffer.unwind if @buffer.last == ','.freeze

      @buffer.to_s
    end

    def inspect
      "#<#{Template}>"
    end

    private

    # Check for the presence of a single-definition flag on the implicit
    # stack. Calls which add one-and-only-one set of values to the buffer
    # in a given stack context will add this flag to tell subsequent
    # calls that they are invalid in that context. `implicitly_close` removes
    # a single-definition flag if it is present.
    def check_for_single!
      if @implicit_stack.last == :single
        raise 'Cannot have second definition in single-definition context'
      end
    end

    # Called as a pre-condition by key-value-defining methods to set up
    # the JSON block definition for those keys and values.
    def implicitly_open kind
      return unless @is_first

      case kind
      when :object
        @buffer << '{'.freeze
      else
        raise "Cannot open kind: #{kind.inspect}"
      end

      @implicit_stack << kind
      @is_first = false
    end

    # Called as a post-condition of methods that build outer structures
    # (arrays and objects) after they've processed their members. Also removes
    # a single-definition flag from the top of the stack if it is present.
    def implicitly_close
      @buffer.unwind if @buffer.last == ','.freeze

      kind = @implicit_stack.pop

      case kind
      when :object
        @buffer << '}'.freeze
      when :array
        @buffer << ']'.freeze
      when :single
        return
      else
        raise "Cannot close kind: #{kind.inspect}"
      end
    end

    def to_json value
      Template.adapter.dump value
    end

    class << self
      attr_writer :adapter
      attr_accessor :cache_backend

      def adapter
        @adapter ||= ::MultiJson.current_adapter
      end
    end

  end# Template
end# Jblazer

require 'jblazer/railtie' if defined? Rails
