# frozen_string_literal: true

module ExampleLoader
  ROOT = File.expand_path('..', __dir__)

  def self.load_example(relative_path, name)
    path = File.join(ROOT, relative_path)
    source = File.read(path)
    marker = "<!-- example: #{name} -->\n```ruby\n"
    raise "example marker missing or duplicated: #{name}" unless source.scan(marker).size == 1

    start = source.index(marker) + marker.length
    finish = source.index("\n```", start) or raise "unclosed example: #{name}"
    # Execute the documented code itself, not a test-only copy.
    TOPLEVEL_BINDING.eval(source[start...finish], path, source[0...start].count("\n") + 1)
  end
end
