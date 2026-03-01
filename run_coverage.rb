#!/usr/bin/env ruby
# frozen_string_literal: true

# Patch bashcov for bats-core compatibility on macOS.
#
# Problem: bats-core runs tests in subshells, causing concurrent xtrace pipe
# writes. When PS4 expansion exceeds macOS PIPE_BUF (512 bytes), writes become
# non-atomic, producing misaligned fields that crash bashcov's parser.
#
# Fix: Replace the anonymous pipe with a temp file for xtrace output. File
# writes from processes sharing the same file description are serialized by
# the kernel's inode lock, eliminating interleaving regardless of write size.
#
# Optimization: A pump thread tails the temp file concurrently while tests
# run, feeding data through an internal pipe to the parser. This overlaps
# test execution with xtrace parsing, significantly reducing wall time.

require "securerandom"
require "tempfile"
require "bashcov/xtrace"
require "bashcov/runner"

# Use a shorter delimiter to further reduce PS4 length
Bashcov::Xtrace.delimiter = SecureRandom.hex(4)

# Patch Xtrace to use a temp file with concurrent pump+parse
module XtraceFilePatch
  def initialize(field_stream)
    @field_stream = field_stream
    @files ||= {}
    @pwd_stack ||= []
    @oldpwd_stack ||= []

    @trace_file = Tempfile.new("bashcov_xtrace")
    @trace_path = @trace_file.path
    @trace_file.close

    # O_WRONLY | O_APPEND ensures atomic append from all child processes
    @write = File.open(@trace_path, "a")

    # Internal pipe: pump thread writes, parser reads
    @pipe_r, @pipe_w = IO.pipe
    @pipe_w.sync = true
    @write_closed = false
    @mutex = Mutex.new
  end

  def file_descriptor
    @write.fileno
  end

  def close
    @write.close unless @write.closed?
    @mutex.synchronize { @write_closed = true }
  end

  # Start a pump thread that tails the temp file and feeds the internal pipe.
  # Call this immediately after spawning the command so parsing can overlap
  # with test execution.
  def start_pump
    @pump_thread = Thread.new do
      f = File.open(@trace_path, "rb")
      begin
        loop do
          begin
            chunk = f.sysread(65_536)
            @pipe_w.write(chunk)
          rescue EOFError
            done = @mutex.synchronize { @write_closed }
            break if done
            sleep 0.02
          end
        end
        # Drain remaining data after writer closed
        loop do
          chunk = f.sysread(65_536)
          @pipe_w.write(chunk)
        rescue EOFError
          break
        end
      ensure
        f.close
        @pipe_w.close
      end
    end
  end

  def read
    @field_stream.read = @pipe_r

    field_count = Bashcov::Xtrace::FIELDS.length
    fields = @field_stream.each(
      self.class.delimiter, field_count, Bashcov::Xtrace::PS4_START_REGEXP
    )

    loop do
      break if (hit = (1..field_count).map { fields.next }).empty?

      begin
        parse_hit!(*hit)
      rescue Bashcov::XtraceError
        # Skip malformed entries (residual from non-atomic writes)
        nil
      end
    end

    @pump_thread&.join
    @pipe_r.close unless @pipe_r.closed?
    File.unlink(@trace_path) if File.exist?(@trace_path)
    @files
  end
end

Bashcov::Xtrace.prepend(XtraceFilePatch)

# Override Runner#run to use concurrent pump+parse
Bashcov::Runner.class_eval do
  alias_method :original_run, :run

  define_method(:run) do
    @result = nil

    field_stream = Bashcov::FieldStream.new
    @xtrace = Bashcov::Xtrace.new(field_stream)
    fd = @xtrace.file_descriptor

    options = { in: :in }
    options[fd] = fd

    if Bashcov.options.mute
      options[:out] = File::NULL
      options[:err] = File::NULL
    end

    # Use BASH_ENV to enable xtrace instead of exporting SHELLOPTS.
    # Exporting SHELLOPTS causes bats-internal options (nounset, pipefail)
    # to propagate to test subprocesses, breaking tests that reference
    # unset environment variables.
    bash_env_file = Tempfile.new("bashcov_bash_env")
    bash_env_file.write("set -x\n")
    bash_env_file.write("export PS4='#{Bashcov::Xtrace.ps4}'\n")
    bash_env_file.close

    env = { "BASH_ENV" => bash_env_file.path }
    env["BASH_XTRACEFD"] = fd.to_s

    begin
      command_pid = Process.spawn(env, *@command, options)

      # Start concurrent pump (file -> pipe) and parse (pipe -> coverage)
      @xtrace.start_pump
      parse_thread = Thread.new { @coverage = @xtrace.read }

      Process.wait command_pid
      @xtrace.close # Signal pump that no more data will be written

      parse_thread.join # Wait for parsing to finish
    rescue Bashcov::XtraceError => e
      warn "bashcov: warning: #{e.message}"
      @coverage = e.files
    end

    $?
  end
end

load Gem.bin_path("bashcov", "bashcov")
