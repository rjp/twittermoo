spec = Gem::Specification.new do |s| 
  s.name = "twittermoo"
  s.version = "0.0.4"
  s.author = "Rob Partington"
  s.email = "zimpenfish@gmail.com"
  s.homepage = "http://rjp.github.com/twittermoo"
  s.platform = Gem::Platform::RUBY
  s.summary = "Simple Twitter-to-Socket gateway"
  s.files = ['bin/twittermoo.rb']
  s.require_path = "lib"
  s.test_files = []
  s.has_rdoc = false
  s.add_dependency('twitter', '>= 0.5')
end

