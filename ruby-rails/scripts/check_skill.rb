# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'rbconfig'
require 'open3'

root = Pathname.new(ARGV.fetch(0, File.expand_path('..', __dir__))).realpath
errors = []
entry = root.join('SKILL.md').read
front = entry.match(/\A---\n(.*?)\n---\n/m)
if front
  begin
    data = YAML.safe_load(front[1])
    valid_name = data.is_a?(Hash) && data['name'].is_a?(String) &&
      data['name'].match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) && data['name'].length <= 64
    errors << 'invalid skill name or folder mismatch' unless valid_name && data['name'] == root.basename.to_s
    description = data.is_a?(Hash) && data['description']
    errors << 'invalid description' unless description.is_a?(String) && !description.strip.empty? && description.length <= 1024
  rescue Psych::Exception => error
    errors << "frontmatter: #{error.message}"
  end
else
  errors << 'missing frontmatter'
end

linked = []
root.glob('**/*.md').each do |file|
  fence = nil
  file.each_line.with_index(1) do |line, number|
    match = line.match(/^\s*(`{3,}|~{3,})(.*)$/)
    if match
      marker, suffix = match.captures
      if fence.nil?
        fence = [marker[0], marker.size, number]
      elsif marker[0] == fence[0] && marker.size >= fence[1] && suffix.strip.empty?
        fence = nil
      end
      next
    end
    next if fence

    line.scan(/\[[^\]]*\]\(([^\s)]+)\)/).flatten.each do |target|
      next if target.match?(/\A(?:https?:|mailto:|#)/)

      path = file.dirname.join(target.split('#', 2).first).cleanpath
      if !path.to_s.start_with?(root.to_s + '/') || !path.exist?
        errors << "#{file.relative_path_from(root)}:#{number}: invalid local link #{target}"
      else
        linked << path
      end
    end
  end
  errors << "#{file.relative_path_from(root)}:#{fence[2]}: unclosed fence" if fence
end
root.glob('{references,assets}/**/*').select(&:file?).each do |file|
  errors << "unreferenced resource: #{file.relative_path_from(root)}" unless linked.include?(file)
end
root.glob('scripts/**/*.rb').each do |file|
  output, status = Open3.capture2e(RbConfig.ruby, '-c', file.to_s)
  errors << "#{file.relative_path_from(root)}: #{output}" unless status.success?
end
abort errors.join("\n") unless errors.empty?
puts "PASS: frontmatter, local links, resource references, fences, Ruby syntax (#{RUBY_VERSION})"
