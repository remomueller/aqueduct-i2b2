# Compiling the Gem
# gem build aqueduct-i2b2.gemspec
# gem install ./aqueduct-i2b2-x.x.x.gem
#
# gem push aqueduct-i2b2-x.x.x.gem
# gem list -r aqueduct-i2b2
# gem install aqueduct-i2b2

$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "aqueduct-i2b2/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "aqueduct-i2b2"
  s.version     = Aqueduct::I2b2::VERSION::STRING
  s.authors     = ["Remo Mueller"]
  s.email       = ["remosm@gmail.com"]
  s.homepage    = "https://github.com/remomueller"
  s.summary     = "Connect to an instance of i2b2 through Aqueduct"
  s.description = "Connects to an instance of i2b2 through Aqueduct interface"

  s.files = Dir["{app,config,db,lib}/**/*"] + ["aqueduct-i2b2.gemspec", "CHANGELOG.rdoc", "LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails",     "~> 3.2.1"
  s.add_dependency "aqueduct",  "~> 0.1.0"

  s.add_development_dependency "sqlite3"
end
