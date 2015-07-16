require_relative 'spec_helper'

describe Jblazer::TemplateHandler do
  it 'should be present' do
    expect(subject).to be
  end
end

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

  it 'should compile an array' do
    template = make_template do |json|
      json.array! [1, '2', :'3']
    end

    expect(template.to_s).to eql '[1,"2","3"]'
  end

  it 'should compile an object' do
    template = make_template do |json|
      json.a 'b'
      json.c 1
    end

    expect(template.to_s).to eql '{"a":"b","c":1}'
  end
end
