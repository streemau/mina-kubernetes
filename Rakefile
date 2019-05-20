require "bundler/gem_tasks"
require 'gemfury'
require 'gemfury/command'

# Override rubygem_push to push to gemfury instead when doing `rake release`
module Bundler
  class GemHelper
    def rubygem_push(path)
      ::Gemfury::Command::App.start(['push', path, '--as=streem'])
    end
  end
end