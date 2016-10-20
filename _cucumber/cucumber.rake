require 'rubygems'
require 'parallel'
require 'fileutils'
require_relative '../_lib/github'
require 'report_builder'

task :features do
  cleanup
  p ". . . . HOST TO TEST = #{ENV['HOST_TO_TEST']} . . . ."

  if ENV['RHD_TEST_PROFILE']
    profile = ENV['RHD_TEST_PROFILE']
  else
    profile = 'desktop'
  end

  if ENV['CUCUMBER_TAGS'].to_s.empty?
    tags = nil
  else
    tag_arr = []
    if ENV['CUCUMBER_TAGS'].include?(',')
      tag = ENV['CUCUMBER_TAGS'].split(',')
      tag.each do |cuke_tag|
        tag_arr << "--tags #{cuke_tag}"
      end
      tags = tag_arr.join(' ')
    else
      tags = "--tags #{ENV['CUCUMBER_TAGS']}"
    end
  end

  if ENV['ghprbActualCommit'].to_s.empty?
    status_code = run(profile, tags)
  else
    p 'Sending progress to Github . . . '
    options = {:context => 'Acceptance Tests', :description => 'Acceptance Tests pending', :target_url => ENV['BUILD_URL']}
    GitHub.update_status($github_org, $github_repo, ENV['ghprbActualCommit'], "pending", options)
    status_code = run(profile, tags)
    if status_code == 0
      options[:description] = 'Acceptance Tests finished ok!'
      GitHub.update_status($github_org, $github_repo, ENV['ghprbActualCommit'], "success", options)
    else
      options[:description] = 'Acceptance Tests failed'
      puts GitHub.update_status($github_org, $github_repo, ENV['ghprbActualCommit'], "failure", options)
    end
  end
  puts "Acceptance tests resulted with status code of #{status_code}"
  exit(status_code)
end

task :wip do
  cleanup
  system('cucumber _cucumber -r _cucumber/features/ --tags @wip')
end

task :debugger do
  cleanup
  system('cucumber _cucumber -r _cucumber/features/ --tags @debug')
end

task :debug, :times do |task, args|
  puts "Executing scenario tagged with @debug #{args[:times]} times"
  args[:times].to_i.times { Rake::Task[:debugger].execute }
end

def run(profile, tag)
  tag_string = tag unless tag.eql?(nil)

  if profile.eql?('slow')
    if tag.eql?(nil)
      system("cucumber _cucumber -r _cucumber/features/ -p #{profile}")
    else
      system("cucumber _cucumber -r _cucumber/features/ -p #{profile} #{tag_string}")
    end
  else
    if tag.eql?(nil)
      system("parallel_cucumber _cucumber/features/ -o \"-p #{profile}\" -n 10")
    else
      system("parallel_cucumber _cucumber/features/ -o \"-p #{profile} #{tag_string}\" -n 10")
    end
  end

  test_exit_code = $?.exitstatus
  if test_exit_code != 0
    test_exit_code = rerun
  end
  generate_reports
  test_exit_code
end

def generate_reports

  ReportBuilder.configure do |config|
    config.json_path = '_cucumber/reports/'
    config.report_path = '_cucumber/reports/rhd_test_report'
    config.report_types = [:json, :html]
    config.report_tabs = [:overview, :features, :errors]
    config.report_title = 'RHD Test Results'
    config.compress_images = true
    end
  ReportBuilder.build_report
end

def rerun
  # rerun attempt one
  if File.exist?('cucumber_failures.log') && File.size('cucumber_failures.log') > 0
    puts ('. . . . . There were failures during the test run! Attempt one of rerunning failed scenarios . . . . .')
    system('bundle exec cucumber @cucumber_failures.log -f rerun --out cucumber_failures1.log')
  end
  # rerun attempt two
  if File.exist?('cucumber_failures1.log') && File.size('cucumber_failures1.log') > 0
    puts('. . . . . There were failures during first rerun! Attempt two of rerunning failed scenarios . . . . .')
    system('bundle exec cucumber @cucumber_failures1.log')
  end
  $?.exitstatus
end

def cleanup
  p '. . . . Deleting old reports and screenshots  . . . .'
  File.delete('cucumber_failures.log') if File.exist?('cucumber_failures.log')
  FileUtils.rm_rf('_cucumber/reports')
  Dir.mkdir('_cucumber/reports')
  FileUtils.rm_rf('_cucumber/screenshots')
  Dir.mkdir('_cucumber/screenshots')
end
