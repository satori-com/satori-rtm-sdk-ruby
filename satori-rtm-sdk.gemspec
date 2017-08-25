Gem::Specification.new do |s|
  s.name              = 'satori-rtm-sdk'
  s.version           = '0.0.1.rc1'
  s.summary           = 'Ruby SDK for Satori RTM'
  s.license           = 'BSD-3-Clause'
  s.author            = 'Andrey Vasenin'
  s.email             = 'sdk@satori.com'
  s.homepage          = 'https://github.com/satori-com/satori-rtm-sdk-ruby'

  s.extra_rdoc_files  = %w[README.md]
  s.rdoc_options      = %w[--main README.md --markup markdown]
  s.require_paths     = %w[lib]

  s.files             = %w[README.md CHANGELOG.md] +
                        Dir.glob('lib/**/*.rb')

  s.add_dependency 'websocket', '~> 1.0'
  s.add_dependency 'json', '~> 2.1'

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'websocket-eventmachine-client', '~> 1.2'
  s.add_development_dependency 'rspec_junit_formatter', '~> 0.3.0'
  s.add_development_dependency 'rubocop', '~> 0.49.1'
  s.add_development_dependency 'simplecov', '~> 0.15.0'
  s.add_development_dependency 'yard', '~> 0.9.0'
end
