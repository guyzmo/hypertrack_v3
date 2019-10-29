Gem::Specification.new do |spec|
  spec.name        = 'hypertrack_v3'
  spec.version     = '1.0.0'
  spec.date        = '2019-10-29'
  spec.summary     = "Ruby bindings for the HyperTrack V3 API!"
  spec.description = "Ruby wrapper around HyperTrack's API V3. Refer http://docs.hypertrack.com/ for more information."
  spec.authors     = ["Bernard Pratz"]
  spec.email       = 'guyzmo+pub@m0g.net'
  spec.files       = Dir.glob('lib/**/*.rb')
  spec.homepage    = 'http://rubygems.org/gems/hypertrack_v3'
  spec.license     = 'LGPL-3.0-only'

  spec.add_dependency 'faraday', '~> 0.15.4'
  spec.add_dependency 'nokogiri', '~> 1.8'
  spec.required_ruby_version = '>= 2.0.0'
end
