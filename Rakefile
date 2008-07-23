require 'rubygems'
require 'rake'
require 'rake/gempackagetask'

LEGS_GEMSPEC = eval(File.read('mtest.gemspec'))

Rake::GemPackageTask.new(LEGS_GEMSPEC) do |pkg|
  pkg.need_tar_bz2 = true
end
task :default => "pkg/#{LEGS_GEMSPEC.name}-#{LEGS_GEMSPEC.version}.gem" do
  puts "generated latest version"
end
