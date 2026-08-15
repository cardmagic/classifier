#!/usr/bin/env ruby
# frozen_string_literal: true

# Static checks for the documentation set.
#
# Run from the repository root:
#   ruby .claude/skills/audit-docs/check_docs.rb
#
# Checks that need no Ruby runtime behavior live here. The executable examples
# live in test/docs/documentation_test.rb, which `rake test` runs.

DASHES = { '—' => 'em dash', '–' => 'en dash', '‒' => 'figure dash', '―' => 'horizontal bar' }.freeze

def markdown_files
  (Dir['*.md'] + Dir['docs/**/*.md']).reject { |f| f == 'CLAUDE.md' }.sort
end

def report(findings)
  findings.each { |f| puts "  #{f}" }
  puts '  none' if findings.empty?
  findings.size
end

total = 0

puts 'Dash characters (docs must use plain prose, not em or en dashes):'
total += report(markdown_files.flat_map do |file|
  File.readlines(file).each_with_index.filter_map do |line, index|
    hit = DASHES.keys.find { |d| line.include?(d) }
    "#{file}:#{index + 1}: #{DASHES[hit]} in #{line.strip[0, 70]}" if hit
  end
end)

puts
puts 'Internal links (every relative markdown link must resolve):'
total += report(markdown_files.flat_map do |file|
  dir = File.dirname(file)
  File.read(file).scan(/\[[^\]]*\]\(([^)#][^)]*)\)/).flatten.filter_map do |target|
    next if target.start_with?('http://', 'https://', 'mailto:')

    path = target.split('#').first
    next if path.nil? || path.empty?

    resolved = File.expand_path(path, dir)
    "#{file}: broken link to #{target}" unless File.exist?(resolved)
  end
end)

puts
puts 'Anchors (every relative link with a fragment must hit a real heading):'
total += report(markdown_files.flat_map do |file|
  dir = File.dirname(file)
  File.read(file).scan(/\[[^\]]*\]\(([^)]*#[^)]+)\)/).flatten.filter_map do |target|
    next if target.start_with?('http://', 'https://')

    path, fragment = target.split('#', 2)
    resolved = path.empty? ? file : File.expand_path(path, dir)
    next unless File.exist?(resolved)

    slugs = File.read(resolved).scan(/^#+\s+(.+)$/).flatten.map do |heading|
      heading.downcase.gsub(/[^\w\s-]/, '').strip.gsub(/\s+/, '-')
    end
    "#{file}: no heading ##{fragment} in #{path.empty? ? File.basename(file) : path}" unless slugs.include?(fragment)
  end
end)

puts
puts 'Documented commands exist:'
total += report(
  %w[classifier keywords].filter_map do |exe|
    "exe/#{exe} is documented but missing" unless File.exist?("exe/#{exe}")
  end
)

puts
puts total.zero? ? 'PASS: no static documentation problems.' : "FAIL: #{total} problem(s)."
exit(total.zero? ? 0 : 1)
