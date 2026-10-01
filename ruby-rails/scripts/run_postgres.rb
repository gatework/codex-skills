# frozen_string_literal: true

# Own a temporary cluster; never accepts a business DATABASE_URL.
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

pg_bin = ENV.fetch('PG_BIN', '')
command = ->(name) { pg_bin.empty? ? name : File.join(pg_bin, name) }
run = lambda do |*args|
  output, status = Open3.capture2e(*args)
  raise "#{File.basename(args.first)} failed: #{output}" unless status.success?
end
begin
  run.call(command.call('initdb'), '--version')
  root = Dir.mktmpdir('rr-pg-', '/tmp')
  begin
    data = File.join(root, 'data')
    started = false
    begin
      run.call(command.call('initdb'), '-D', data, '-A', 'trust', '--no-locale', '-E', 'UTF8')
      # Unix socket in mode-0700 private directory; no TCP listener.
      run.call(command.call('pg_ctl'), '-D', data, '-l', File.join(root, 'server.log'),
               '-o', "-k #{root} -h ''", '-w', 'start')
      started = true
      run.call(command.call('createdb'), '-h', root, '-p', '5432', 'ruby_rails_skill_test')
      env = {'RR_PG_ROOT' => root}
      ok = system(env, RbConfig.ruby, File.join(__dir__, 'postgres_test.rb'), *ARGV)
      raise 'PostgreSQL behavior tests failed' unless ok
    ensure
      if started || File.file?(File.join(data, 'postmaster.pid'))
        run.call(command.call('pg_ctl'), '-D', data, '-m', 'fast', '-w', 'stop')
      end
      FileUtils.remove_entry_secure(root)
    end
  rescue StandardError
    warn "Temporary cluster retained for inspection: #{root}" if File.exist?(root)
    raise
  end
rescue Errno::ENOENT, RuntimeError => error
  warn error.message
  warn 'Use PG_BIN=/path/to/postgresql/bin ruby scripts/run_postgres.rb; no shared database is used.'
  exit 1
end
