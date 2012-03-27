# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "danger_zone/version"

Gem::Specification.new do |s|
  s.name        = "danger_zone"
  s.version     = DangerZone::VERSION
  s.authors     = ["Rick Moynihan"]
  s.email       = ["rick@stardotstar.com"]
  s.homepage    = ""
  s.summary     = %q{Infrastructure-less Rack based session storage}
  s.description = %q{Infrastructure-less Rack based session storage}

  s.rubyforge_project = "danger_zone"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "rspec"

  s.add_runtime_dependency "rack"
end
