require 'rake'
require 'rake/testtask'
require 'rdoc/task'

# Try to load rake-compiler for native extension support
begin
  require 'rake/extensiontask'
  Rake::ExtensionTask.new('classifier_ext') do |ext|
    ext.lib_dir = 'lib/classifier'
    ext.ext_dir = 'ext/classifier'
  end
  HAVE_EXTENSION = true
rescue LoadError
  HAVE_EXTENSION = false
end

desc 'Default Task'
task default: HAVE_EXTENSION ? %i[compile test] : [:test]

# Run the unit tests
desc 'Run all unit tests'
Rake::TestTask.new('test') do |t|
  t.libs << 'lib'
  t.pattern = 'test/*/*_test.rb'
  t.verbose = true
end

# Make a console, useful when working on tests
desc 'Generate a test console'
task :console do
  verbose(false) { sh "irb -I lib/ -r 'classifier'" }
end

# Genereate the RDoc documentation
desc 'Create documentation'
Rake::RDocTask.new('doc') do |rdoc|
  rdoc.title = 'Ruby Classifier - Bayesian and LSI classification library'
  rdoc.rdoc_dir = 'html'
  rdoc.rdoc_files.include('README.md')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

# Benchmarks
desc 'Run LSI benchmark with current configuration'
task :benchmark do
  ruby 'benchmark/lsi_benchmark.rb'
end

desc 'Run LSI benchmark comparing GSL vs Native Ruby'
task 'benchmark:compare' do
  ruby 'benchmark/lsi_benchmark.rb --compare'
end

desc 'Report code statistics (KLOCs, etc) from the application'
task :stats do
  require 'code_statistics'
  CodeStatistics.new(
    %w[Library lib],
    %w[Units test]
  ).to_s
end

desc 'Publish new documentation'
task :publish do
  `ssh rufy update-classifier-doc`
  Rake::RubyForgePublisher.new('classifier', 'cardmagic').upload
end

# C Code Coverage tasks
namespace :coverage do # rubocop:disable Metrics/BlockLength
  desc 'Clean C coverage data files'
  task :clean do
    FileUtils.rm_f(Dir.glob('ext/classifier/**/*.gcda'))
    FileUtils.rm_f(Dir.glob('ext/classifier/**/*.gcno'))
    FileUtils.rm_f(Dir.glob('tmp/**/classifier/**/*.gcda'))
    FileUtils.rm_f(Dir.glob('tmp/**/classifier/**/*.gcno'))
    FileUtils.rm_rf('coverage/c')
  end

  desc 'Compile C extension with coverage instrumentation'
  task :compile do
    ENV['COVERAGE'] = '1'
    Rake::Task['clobber'].invoke if Rake::Task.task_defined?('clobber')
    Rake::Task['compile'].reenable
    Rake::Task['compile'].invoke
  end

  desc 'Generate C coverage report using lcov'
  task :report do # rubocop:disable Metrics/BlockLength
    project_root = File.expand_path(__dir__)
    ext_dir = File.join(project_root, 'ext/classifier')
    # Find the directory containing .gcda files (build directory varies by platform/Ruby version)
    tmp_ext_dir = Dir.glob('tmp/**/classifier_ext/**/*.gcda').first&.then { |f| File.dirname(f) }
    coverage_dir = 'coverage/c'

    unless tmp_ext_dir
      puts 'No coverage data found. Run tests with coverage first.'
      next
    end

    FileUtils.mkdir_p(coverage_dir)

    # Run gcov manually in the build directory to generate .gcov files
    Dir.chdir(tmp_ext_dir) do
      # Find all source files and run gcov on them
      gcda_files = Dir.glob('*.gcda')
      gcda_files.each do |gcda|
        # Source file is in ext/classifier, referenced via relative path in the gcno
        sh "gcov -o . #{gcda} 2>/dev/null || true"
      end
    end

    # Capture coverage data with base directory for source resolution
    sh "lcov --capture --directory #{tmp_ext_dir} --base-directory #{ext_dir} " \
       "--output-file #{coverage_dir}/coverage.info " \
       '--ignore-errors inconsistent,gcov,source 2>&1 || true'

    if File.exist?("#{coverage_dir}/coverage.info") && File.size("#{coverage_dir}/coverage.info").positive?
      # Filter out system headers
      sh "lcov --remove #{coverage_dir}/coverage.info '/usr/*' '*/ruby/*' " \
         "--output-file #{coverage_dir}/coverage.info --ignore-errors unused 2>/dev/null || true"

      # Fix source paths: the gcov relative paths resolve incorrectly
      # Substitute wrong paths with correct absolute paths
      info_content = File.read("#{coverage_dir}/coverage.info")
      info_content.gsub!(%r{SF:.*/ext/classifier/}, "SF:#{ext_dir}/")
      File.write("#{coverage_dir}/coverage.info", info_content)

      # Generate HTML report
      sh "genhtml #{coverage_dir}/coverage.info --output-directory #{coverage_dir}/html " \
         "--prefix #{project_root} --ignore-errors unmapped,source 2>&1 || true"

      puts "\nC coverage report generated at: #{coverage_dir}/html/index.html"

      # Print summary
      sh "lcov --summary #{coverage_dir}/coverage.info 2>/dev/null || true"
    else
      puts 'Coverage data capture failed. Check that tests exercise the C extension.'
    end
  end

  desc 'Run tests and generate C coverage report'
  task :run do
    Rake::Task['coverage:clean'].invoke
    Rake::Task['coverage:compile'].invoke
    Rake::Task['test'].invoke
    Rake::Task['coverage:report'].invoke
  end
end

desc 'Run C code coverage (alias for coverage:run)'
task 'coverage:c' => 'coverage:run'
