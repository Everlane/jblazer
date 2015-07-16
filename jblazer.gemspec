Gem::Specification.new do |s|
  s.name     = 'jblazer'
  s.version  = '0.0.1'
  s.authors  = ['Dirk Gadsden']
  s.email    = ['dirk@esherido.com']
  s.summary  = 'Fast JSON generator and drop-in replacement for Jbuilder'
  s.homepage = 'https://github.com/Everlane/jblazer'
  s.license  = 'MIT'

  s.required_ruby_version = '>= 1.9.3'

  s.add_dependency 'activesupport', '>= 3.0.0', '< 5'
  s.add_dependency 'multi_json',    '~> 1.2'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- test/*`.split("\n")
end
