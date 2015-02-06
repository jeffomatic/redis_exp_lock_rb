# encoding: utf-8
$:.unshift File.expand_path("../lib", __FILE__)
require 'redis_exp_lock/version'

Gem::Specification.new do |s|
  s.name = 'redis_exp_lock'
  s.licenses = ['MIT']
  s.summary = "Distributed mutual exclusion using Redis"
  s.version = RedisExpLock::VERSION
  s.homepage = 'https://github.com/jeffomatic/redis_exp_lock_rb'

  s.authors = ["Jeff Lee"]
  s.email = 'jeffomatic@gmail.com'

  s.files = %w( README.md LICENSE redis_exp_lock.gemspec )
  s.files += Dir.glob('lib/**/*')

  s.add_runtime_dependency('shavaluator', '~>0.1')

  s.add_development_dependency('rspec', '~>3.1.0')
  s.add_development_dependency('redis', '~>3.2.0')
end