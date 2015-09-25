require 'active_support/json/encoding'

module Jblazer
  class UnwindableBuffer
    def initialize
      @contents = []
    end

    def <<(item)
      @contents << item
    end

    def to_s
      @contents.map(&:strip).join ''
    end

    def last
      @contents.last
    end

    def unwind
      @contents.pop
    end
  end

  class Template
    attr_reader :buffer, :context
    attr_accessor :cache_backend

    def initialize context
      @context = context
      @buffer = UnwindableBuffer.new

      @cache_backend = ::Rails.cache if defined?(Rails) && Rails.respond_to?(:cache)

      # Keeps track of structures implicitly opened and closed
      @implicit_stack = []
      # If we're evaluating the first item in a potentially-implicit structure
      @is_first = true
    end

    def array! items, &block
      check_for_single!

      @buffer << "["

      # If we're the first definition in an implicit object then
      # we'll assume we're the ONLY definition in that object.
      if @is_first && @implicit_stack.last == :object
        @implicit_stack << :single
      end

      depth = @implicit_stack.length

      last_index = items.length - 1

      items.each_with_index do |item, index|
        @is_first = true

        if block.nil?
          @buffer << item.to_json
        else
          block.call item
        end

        # Close whatever was opened by the item
        implicitly_close if @implicit_stack.length > depth

        @buffer << "," unless index == last_index
      end

      @is_first = false
      @buffer << "]"
    end

    def partial! name, opts
      check_for_single!

      raise ':collection not supported yet' if opts[:collection]
      raise ':as not supported yet' if opts[:as]

      locals = opts.delete(:locals) || {}

      locals.merge! opts

      ret = @context.render :partial => name, :locals => locals

      @buffer << ret
    end

    def extract! obj, *keys
      check_for_single!
      implicitly_open :object

      is_hash = obj.kind_of? Hash

      keys.each do |key|
        value = is_hash ? obj[key] : obj.send(key)
        @buffer << key.to_json
        @buffer << ':'
        @buffer << value.to_json
        @buffer << ","
      end
    end

    def compute_cache_key key
      key
    end

    def cache! key, opts={}, &block
      cache_key = compute_cache_key key

      depth = @implicit_stack.length

      value = @cache_backend.fetch(cache_key, opts) do
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

      @buffer << 'null'

      @is_first = false
    end

    def method_missing name, *args, &block
      check_for_single! if args.any?
      implicitly_open :object

      @buffer << name.to_json
      @buffer << ':'

      if args.length > 1
        raise "Too many arguments (max is 1, got #{args.length})"

      elsif args.length == 1 && !block.nil?
        array! args.first, &block

      elsif args.length == 1
        @buffer << args.first.to_json

      elsif !block.nil?
        implicitly_open :object

        @is_first = true

        block.call self

        implicitly_close

      else
        raise "Missing value argument for '#{name}'"
      end

      @buffer << ","
    end

    def to_s
      implicitly_close if @implicit_stack.length > 0

      @buffer.unwind if @buffer.last == ","

      @buffer.to_s
    end

    private

    def check_for_single!
      if @implicit_stack.last == :single
        raise "Cannot have second definition in single-definition context"
      end
    end

    # Called as a pre-condition by key-value-defining methods to set up
    # the JSON block definition for those keys and values.
    def implicitly_open kind
      return unless @is_first

      case kind
      when :object
        @buffer << "{"
      else
        raise "Cannot open kind: #{kind.inspect}"
      end

      @implicit_stack << kind
      @is_first = false
    end

    # Called as a post-condition of methods that build outer structures
    # (arrays and objects) after they've processed each member.
    def implicitly_close
      @buffer.unwind if @buffer.last == ","

      kind = @implicit_stack.pop

      case kind
      when :object
        @buffer << '}'
      when :array
        @buffer << ']'
      when :single
        return
      else
        raise "Cannot close kind: #{kind.inspect}"
      end
    end

  end# Template
end# Jblazer

require 'jblazer/railtie' if defined? Rails
