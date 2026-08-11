# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'yard'

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop)

YARD::Rake::YardocTask.new(:yard)

desc 'Run the Sorbet type checker'
task :typecheck do
  sh 'srb tc'
end

desc 'Check dependencies for known vulnerabilities'
task :audit do
  # bundler-audit checks the gems in the bundle; ruby-audit checks the Ruby
  # and RubyGems the bundle runs on. Both read the same advisory database, so
  # they are the same concern — known CVEs — at two levels.
  sh 'bundle-audit check --update'
  sh 'ruby-audit check'
end

desc 'Check that every dependency carries an approved licence'
task :licenses do
  sh 'license_finder'
end

desc 'Run mutation testing (slow; not part of the default task)'
task :mutant do
  # SimpleCov's per-run coverage floor would fail on every mutation run, and
  # measuring coverage hundreds of times is wasted work regardless.
  ENV['SKIP_COVERAGE'] = '1'
  sh 'mutant run --usage opensource'
end

namespace :doc do
  desc 'Fail if any object is undocumented'
  task :coverage do
    require 'open3'

    output, status = Open3.capture2e('yard', 'stats', '--list-undoc')
    abort "yard stats failed:\n#{output}" unless status.success?

    puts output

    documented = output[/([\d.]+)% documented/, 1]
    abort 'Could not parse documentation coverage from yard stats' if documented.nil?

    abort "Documentation coverage is #{documented}%, expected 100%" unless documented.to_f >= 100.0
  end

  desc 'Check YARD tags for errors and stale references'
  task :lint do
    sh 'yard-junk --text'
  end

  desc 'Build the docs site with MkDocs and the Material theme into site/'
  task :site do
    # --strict turns any warning, such as a link that does not resolve, into
    # a failure: the docs build should pass or say why.
    sh 'mkdocs build --strict'
  end
end

desc 'Run every check that is fast enough to run constantly'
task default: %i[rubocop typecheck spec doc:coverage doc:lint]
