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

    def initialize context
      @context = context
      @buffer = UnwindableBuffer.new

      # Keeps track of structures implicitly opened and closed
      @implicit_stack = []
      # If we're evaluating the first item in a potentially-implicit structure
      @is_first = true
    end

    def array! items, &block
      @buffer << "["

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

      @buffer << "]"
    end

    def implicitly_close
      @buffer.unwind if @buffer.last == ","

      kind = @implicit_stack.pop
      
      case kind
      when :object
        @buffer << "}"
      else
        raise "Cannot close kind: #{kind.inspect}"
      end
    end

    def partial! name, opts
      raise ':collection not supported yet' if opts[:collection]
      raise ':as not supported yet' if opts[:as]

      locals = opts.delete(:locals) || {}

      locals.merge! opts

      ret = @context.render :partial => name, :locals => locals

      @buffer << ret
    end

    def method_missing name, *args, &block
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
        @is_first = true

        implicitly_open :object

        block.call self

        implicitly_close

      else
        raise "Missing value argument for '#{name}'"
      end

      @buffer << ","
    end

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

    def extract! obj, *keys
      implicitly_open :object

      keys.each do |key|
        @buffer << key.to_json
        @buffer << ':'
        @buffer << obj.send(key).to_json
        @buffer << ","
      end
    end


    def to_s
      implicitly_close if @implicit_stack.length > 0

      @buffer.to_s
    end
  end
end

require 'jblazer/railtie' if defined? Rails
