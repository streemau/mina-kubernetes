# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mina/kubernetes/version'

Gem::Specification.new do |spec|
  spec.name          = 'mina-kubernetes'
  spec.version       = Mina::Kubernetes::VERSION
  spec.authors       = ['Antoine Sabourin']
  spec.email         = ['antoine@streem.com.au']

  spec.summary       = %q{Mina plugin to streamline deployment of resources to Kubernetes cluster}
  spec.description   = %q{Mina plugin to streamline deployment of resources to Kubernetes cluster}
  spec.homepage      = 'https://github.com/streemau/mina-kubernetes'
  spec.license       = 'MIT'

  spec.files = `git ls-files -z`.split("\x0")
  spec.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
  spec.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'bundler', '~> 1.11'
  spec.add_development_dependency 'rake', '>= 12.3.3'

  spec.add_runtime_dependency 'mina', '~> 1.0'
  spec.add_runtime_dependency 'mina-multistage', '~> 1.0'
  spec.add_runtime_dependency 'krane', '~> 3'
  spec.add_runtime_dependency 'tty-prompt'
  spec.add_runtime_dependency 'tty-spinner'
end
