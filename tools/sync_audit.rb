#!/usr/bin/env ruby
# encoding: utf-8
# DMSA file sync audit tool
# Used to check file sync status between LOCAL_DIR and EXTERNAL_DIR

require 'find'
require 'digest'
require 'json'
require 'optparse'
require 'fileutils'

class SyncAuditor
  # Excluded file/directory patterns (consistent with DMSA)
  EXCLUDE_PATTERNS = [
    '.DS_Store',
    '.Spotlight-V100',
    '.Trashes',
    '.fseventsd',
    '.TemporaryItems',
    '.FUSE',
    '.index_cache',
    '.git',
  ]

  # Excluded filename patterns (regex)
  EXCLUDE_REGEX = [
    /^\._/,           # macOS resource forks
    /~$/,             # vim backup files
    /\.un~$/,         # vim undo files
    /\.swp$/,         # vim swap files
  ]

  def initialize(local_dir, external_dir, options = {})
    @local_dir = File.expand_path(local_dir)
    @external_dir = File.expand_path(external_dir)
    @options = options
    @verbose = options[:verbose] || false
    @check_content = options[:check_content] || false
    @output_file = options[:output]

    @results = {
      local_only: [],
      external_only: [],
      both: [],
      size_mismatch: [],
      content_mismatch: [],
      excluded: [],
      errors: []
    }

    @stats = {
      local_files: 0,
      external_files: 0,
      local_size: 0,
      external_size: 0,
      scanned_local: 0,
      scanned_external: 0
    }
  end

  def run
    puts "=" * 60
    puts "DMSA File Sync Audit"
    puts "=" * 60
    puts "LOCAL_DIR:    #{@local_dir}"
    puts "EXTERNAL_DIR: #{@external_dir}"
    puts "=" * 60
    puts ""

    # Validate directories
    unless File.directory?(@local_dir)
      puts "❌ Error: LOCAL_DIR does not exist: #{@local_dir}"
      return false
    end

    unless File.directory?(@external_dir)
      puts "❌ Error: EXTERNAL_DIR does not exist: #{@external_dir}"
      return false
    end

    # Scan files
    puts "📂 Scanning LOCAL_DIR..."
    local_files = scan_directory(@local_dir)
    @stats[:local_files] = local_files.size
    puts "   Found #{local_files.size} files"

    puts "📂 Scanning EXTERNAL_DIR..."
    external_files = scan_directory(@external_dir)
    @stats[:external_files] = external_files.size
    puts "   Found #{external_files.size} files"

    puts ""
    puts "🔍 Comparing files..."
    compare_files(local_files, external_files)

    # Output results
    print_results

    # Save report
    if @output_file
      save_report
    end

    true
  end

  private

  def scan_directory(base_dir)
    files = {}

    Find.find(base_dir) do |path|
      # Skip root directory
      next if path == base_dir

      # Get relative path and perform Unicode NFC normalization
      rel_path = path.sub("#{base_dir}/", '')
      rel_path = rel_path.encode('UTF-8', invalid: :replace, undef: :replace).unicode_normalize(:nfc) rescue rel_path

      # Check if excluded
      basename = File.basename(path)
      dirname = File.dirname(rel_path)

      if should_exclude?(basename, dirname)
        @results[:excluded] << rel_path if File.file?(path)
        Find.prune if File.directory?(path)
        next
      end

      # Only process files
      next unless File.file?(path)

      begin
        stat = File.stat(path)
        files[rel_path] = {
          path: path,
          size: stat.size,
          mtime: stat.mtime
        }

        if base_dir == @local_dir
          @stats[:local_size] += stat.size
          @stats[:scanned_local] += 1
        else
          @stats[:external_size] += stat.size
          @stats[:scanned_external] += 1
        end
      rescue => e
        @results[:errors] << { path: rel_path, error: e.message }
      end
    end

    files
  end

  def should_exclude?(basename, dirname)
    # Check exact match
    return true if EXCLUDE_PATTERNS.include?(basename)

    # Check if directory path contains excluded items
    EXCLUDE_PATTERNS.each do |pattern|
      return true if dirname.split('/').include?(pattern)
    end

    # Check regex patterns
    EXCLUDE_REGEX.each do |regex|
      return true if basename =~ regex
    end

    false
  end

  def compare_files(local_files, external_files)
    all_paths = (local_files.keys + external_files.keys).uniq

    all_paths.each do |rel_path|
      local_info = local_files[rel_path]
      external_info = external_files[rel_path]

      if local_info && external_info
        # Exists on both sides
        @results[:both] << rel_path

        # Check size
        if local_info[:size] != external_info[:size]
          @results[:size_mismatch] << {
            path: rel_path,
            local_size: local_info[:size],
            external_size: external_info[:size]
          }
        elsif @check_content
          # Check content (MD5)
          local_md5 = Digest::MD5.file(local_info[:path]).hexdigest rescue nil
          external_md5 = Digest::MD5.file(external_info[:path]).hexdigest rescue nil

          if local_md5 && external_md5 && local_md5 != external_md5
            @results[:content_mismatch] << {
              path: rel_path,
              local_md5: local_md5,
              external_md5: external_md5
            }
          end
        end
      elsif local_info
        # Local only
        @results[:local_only] << {
          path: rel_path,
          size: local_info[:size]
        }
      else
        # External only
        @results[:external_only] << {
          path: rel_path,
          size: external_info[:size]
        }
      end
    end
  end

  def print_results
    puts ""
    puts "=" * 60
    puts "📊 Audit Results"
    puts "=" * 60

    puts ""
    puts "📈 Statistics:"
    puts "   LOCAL_DIR  file count: #{@stats[:scanned_local]}"
    puts "   LOCAL_DIR  total size: #{format_size(@stats[:local_size])}"
    puts "   EXTERNAL_DIR file count: #{@stats[:scanned_external]}"
    puts "   EXTERNAL_DIR total size: #{format_size(@stats[:external_size])}"

    puts ""
    puts "📋 Sync Status:"
    puts "   ✅ Both sides:     #{@results[:both].size}"
    puts "   📤 Local only:     #{@results[:local_only].size}"
    puts "   📥 External only:  #{@results[:external_only].size}"
    puts "   ⚠️  Size mismatch:  #{@results[:size_mismatch].size}"
    puts "   ❌ Content mismatch: #{@results[:content_mismatch].size}" if @check_content
    puts "   🚫 Excluded:       #{@results[:excluded].size}"
    puts "   ⛔ Errors:         #{@results[:errors].size}"

    # Detailed output
    if @verbose || @results[:local_only].size <= 20
      if @results[:local_only].any?
        puts ""
        puts "📤 Files only on local (need to sync to external):"
        @results[:local_only].first(50).each do |info|
          puts "   - #{info[:path]} (#{format_size(info[:size])})"
        end
        if @results[:local_only].size > 50
          puts "   ... and #{@results[:local_only].size - 50} more files"
        end
      end
    end

    if @verbose || @results[:external_only].size <= 20
      if @results[:external_only].any?
        puts ""
        puts "📥 Files only on external (missing locally):"
        @results[:external_only].first(50).each do |info|
          puts "   - #{info[:path]} (#{format_size(info[:size])})"
        end
        if @results[:external_only].size > 50
          puts "   ... and #{@results[:external_only].size - 50} more files"
        end
      end
    end

    if @results[:size_mismatch].any?
      puts ""
      puts "⚠️  Files with size mismatch:"
      @results[:size_mismatch].first(20).each do |info|
        puts "   - #{info[:path]}"
        puts "     LOCAL: #{format_size(info[:local_size])}, EXTERNAL: #{format_size(info[:external_size])}"
      end
      if @results[:size_mismatch].size > 20
        puts "   ... and #{@results[:size_mismatch].size - 20} more files"
      end
    end

    if @results[:content_mismatch].any?
      puts ""
      puts "❌ Files with content mismatch (same size but different MD5):"
      @results[:content_mismatch].first(20).each do |info|
        puts "   - #{info[:path]}"
      end
    end

    if @results[:errors].any?
      puts ""
      puts "⛔ Errors:"
      @results[:errors].first(10).each do |info|
        puts "   - #{info[:path]}: #{info[:error]}"
      end
    end

    puts ""
    puts "=" * 60

    # Summary
    if @results[:local_only].empty? && @results[:external_only].empty? &&
       @results[:size_mismatch].empty? && @results[:content_mismatch].empty?
      puts "✅ Sync status: Fully consistent"
    else
      puts "⚠️  Sync status: Differences found"
      puts ""
      puts "Suggested actions:"
      if @results[:local_only].any?
        puts "   - Run sync to push #{@results[:local_only].size} local files to external"
      end
      if @results[:external_only].any?
        puts "   - Check whether #{@results[:external_only].size} external-only files need to be restored locally"
      end
      if @results[:size_mismatch].any?
        puts "   - Inspect #{@results[:size_mismatch].size} files with size mismatch"
      end
    end

    puts "=" * 60
  end

  def save_report
    report = {
      timestamp: Time.now.iso8601,
      local_dir: @local_dir,
      external_dir: @external_dir,
      stats: @stats,
      results: {
        both_count: @results[:both].size,
        local_only: @results[:local_only],
        external_only: @results[:external_only],
        size_mismatch: @results[:size_mismatch],
        content_mismatch: @results[:content_mismatch],
        excluded_count: @results[:excluded].size,
        errors: @results[:errors]
      }
    }

    File.write(@output_file, JSON.pretty_generate(report))
    puts ""
    puts "📄 Report saved to: #{@output_file}"
  end

  def format_size(bytes)
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    unit_index = 0
    size = bytes.to_f

    while size >= 1024 && unit_index < units.size - 1
      size /= 1024
      unit_index += 1
    end

    "%.2f %s" % [size, units[unit_index]]
  end
end

# Command line parsing
options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] [LOCAL_DIR] [EXTERNAL_DIR]"
  opts.separator ""
  opts.separator "DMSA file sync audit tool"
  opts.separator ""
  opts.separator "Options:"

  opts.on("-v", "--verbose", "Verbose output") do
    options[:verbose] = true
  end

  opts.on("-c", "--check-content", "Check file content (MD5, slower)") do
    options[:check_content] = true
  end

  opts.on("-o", "--output FILE", "Save JSON report to file") do |file|
    options[:output] = file
  end

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit
  end
end

parser.parse!

# Default directories
local_dir = ARGV[0] || File.expand_path("~/Downloads_Local")
external_dir = ARGV[1] || "/Volumes/BACKUP/Downloads"

# Run audit
auditor = SyncAuditor.new(local_dir, external_dir, options)
exit(auditor.run ? 0 : 1)
