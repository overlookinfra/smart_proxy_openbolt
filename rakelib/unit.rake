# frozen_string_literal: true

require 'rake/testtask'

desc 'Run unit tests.'
Rake::TestTask.new(:test) do |task|
  task.libs << '.'
  task.libs << 'lib'
  task.libs << 'test'
  task.test_files = FileList['test/unit/**/*_test.rb']
  task.options = '--verbose'
  task.verbose = true
  task.warning = false
end
