#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# pbxproj management tool (Ruby version)
# Uses CocoaPods xcodeproj gem
#
# Usage:
#   bundle exec ruby pbxproj_tool.rb <command> [options]
#
# Commands:
#   list [pattern]              List all files in the project (optional filter)
#   list-targets                List all build targets
#   find <pattern>              Find matching files
#   info <filename>             Show file details
#   add <file> <target>         Add file to target
#   add-multi <target> <files>  Batch add files to target
#   remove <file1> [file2...]   Remove file references
#   check                       Check project integrity
#   fix                         Fix broken references
#   smart-fix [--dry-run]       Smart fix (detect unadded files and auto-add)
#   backup                      Manually backup project file
#   restore [backup_name]       Restore backup

# Force UTF-8 encoding
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'xcodeproj'
require 'fileutils'

# Auto-detect project path
def find_project_path
  candidates = [
    'DMSAApp.xcodeproj',
    'DMSAApp/DMSAApp.xcodeproj',
    '../DMSAApp/DMSAApp.xcodeproj'
  ]

  candidates.each do |path|
    return path if File.exist?(path)
  end

  raise "Cannot find DMSAApp.xcodeproj (searched paths: #{candidates.join(', ')})"
end

PROJECT_PATH = find_project_path
# Backup directory is always at the project root
BACKUP_DIR = File.expand_path('../.pbxproj_backups', PROJECT_PATH)

class PBXProjTool
  def initialize
    # Ensure files are read with UTF-8 encoding
    @project = Xcodeproj::Project.open(PROJECT_PATH)
    @project_dir = File.dirname(File.expand_path(PROJECT_PATH))
  end

  # Backup project file
  def backup
    FileUtils.mkdir_p(BACKUP_DIR)
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_path = File.join(BACKUP_DIR, "project.pbxproj.#{timestamp}")
    FileUtils.cp("#{PROJECT_PATH}/project.pbxproj", backup_path)
    puts "✓ Backed up to: #{backup_path}"
    backup_path
  end

  # Restore backup
  def restore(backup_name = nil)
    unless Dir.exist?(BACKUP_DIR)
      puts "✗ Backup directory does not exist: #{BACKUP_DIR}"
      return false
    end

    backups = Dir.glob("#{BACKUP_DIR}/project.pbxproj.*").sort
    if backups.empty?
      puts "✗ No backup files found"
      return false
    end

    if backup_name
      backup_path = backups.find { |b| b.include?(backup_name) }
      unless backup_path
        puts "✗ Cannot find backup: #{backup_name}"
        puts "Available backups:"
        backups.each { |b| puts "  - #{File.basename(b)}" }
        return false
      end
    else
      # Use latest backup
      backup_path = backups.last
    end

    # Backup current file first
    current_backup = backup
    puts "Current file backed up to: #{current_backup}"

    # Restore
    FileUtils.cp(backup_path, "#{PROJECT_PATH}/project.pbxproj")
    puts "✓ Restored from #{File.basename(backup_path)}"
    true
  end

  # List all backups
  def list_backups
    unless Dir.exist?(BACKUP_DIR)
      puts "No backup directory"
      return []
    end

    backups = Dir.glob("#{BACKUP_DIR}/project.pbxproj.*").sort
    if backups.empty?
      puts "No backup files"
      return []
    end

    puts "\nAvailable backups:"
    puts "-" * 50
    backups.each do |b|
      size = File.size(b)
      mtime = File.mtime(b)
      puts "  #{File.basename(b)} (#{format_size(size)}, #{mtime.strftime('%Y-%m-%d %H:%M:%S')})"
    end
    puts "-" * 50
    puts "Total: #{backups.count} backups"
    backups
  end

  # List all files
  def list_files(pattern = nil)
    puts "\nProject file list:"
    puts "-" * 80

    files = @project.files.sort_by { |f| f.path&.downcase || '' }
    count = 0

    files.each do |file|
      next unless file.path
      next if pattern && !file.path.downcase.include?(pattern.downcase)

      type = file.last_known_file_type || file.explicit_file_type || '?'
      type_short = type.split('.').last
      puts "  [#{type_short.ljust(10)}] #{file.path}"
      count += 1
    end

    puts "-" * 80
    puts "Total: #{count} files" + (pattern ? " (matching '#{pattern}')" : "")
  end

  # List all targets
  def list_targets
    puts "\nBuild targets:"
    puts "-" * 60

    @project.targets.each do |target|
      type = target.product_type&.split('.')&.last || '?'
      files_count = target.source_build_phase&.files&.count || 0
      puts "  [#{type.ljust(12)}] #{target.name} (#{files_count} source files)"
    end

    puts "-" * 60
    puts "Total: #{@project.targets.count} targets"
  end

  # Find files
  def find_files(pattern)
    puts "\nSearching files: '#{pattern}'"
    puts "-" * 80

    results = []
    @project.files.each do |file|
      next unless file.path
      if file.path.downcase.include?(pattern.downcase)
        results << file
      end
    end

    if results.empty?
      puts "No matching files found"
    else
      results.each do |file|
        # Find targets containing this file
        targets = find_targets_for_file(file)
        targets_str = targets.empty? ? "(not added to any target)" : targets.join(', ')
        puts "  #{file.path}"
        puts "    -> Targets: #{targets_str}"
      end
      puts "-" * 80
      puts "Found #{results.count} matching files"
    end
    results
  end

  # Show file details
  def file_info(filename)
    puts "\nFile info: '#{filename}'"
    puts "-" * 60

    file = @project.files.find { |f| f.path&.end_with?(filename) }
    unless file
      puts "✗ File not found: #{filename}"
      return nil
    end

    puts "Path:       #{file.path}"
    puts "Type:       #{file.last_known_file_type || file.explicit_file_type || 'unknown'}"
    puts "Source tree: #{file.source_tree}"
    puts "UUID:       #{file.uuid}"

    # Full path
    full_path = build_path_from_group(file)
    puts "Full path:  #{full_path}"
    puts "File exists: #{File.exist?(full_path) ? '✓ Yes' : '✗ No'}"

    # Find containing targets
    targets = find_targets_for_file(file)
    if targets.any?
      puts "Targets:    #{targets.join(', ')}"
    else
      puts "Targets:    (not added to any target)"
    end

    # Parent group info
    if file.parent
      puts "Parent group: #{file.parent.display_name rescue file.parent.path}"
    end

    puts "-" * 60
    file
  end

  # Add file to target
  def add_file(file_path, target_name)
    unless File.exist?(file_path)
      puts "✗ File does not exist: #{file_path}"
      return false
    end

    target = @project.targets.find { |t| t.name == target_name }
    unless target
      puts "✗ Target does not exist: #{target_name}"
      puts "Available targets: #{@project.targets.map(&:name).join(', ')}"
      return false
    end

    # Check if already exists
    file_name = File.basename(file_path)
    existing = @project.files.find { |f| f.path&.end_with?(file_name) }
    if existing
      puts "! File already exists in project: #{existing.path}"
      # Check if already in target
      if find_targets_for_file(existing).include?(target_name)
        puts "  and already in target #{target_name}"
        return true
      end
      # Add to target
      if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
        target.source_build_phase.add_file_reference(existing)
        @project.save
        puts "✓ Added to target: #{target_name}"
        return true
      end
    end

    backup

    # Find or create group
    group = find_or_create_group_for_file(file_path)

    # Add file reference - use filename only
    file_ref = group.new_file(file_name)

    # Add to target's compile sources
    if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
      target.source_build_phase.add_file_reference(file_ref)
    end

    @project.save
    puts "✓ Added: #{file_path} -> #{target_name}"
    true
  end

  # Batch add files
  def add_files(file_paths, target_name)
    target = @project.targets.find { |t| t.name == target_name }
    unless target
      puts "✗ Target does not exist: #{target_name}"
      puts "Available targets: #{@project.targets.map(&:name).join(', ')}"
      return false
    end

    backup
    added = 0
    skipped = 0

    file_paths.each do |file_path|
      unless File.exist?(file_path)
        puts "✗ File does not exist: #{file_path}"
        next
      end

      file_name = File.basename(file_path)
      existing = @project.files.find { |f| f.path&.end_with?(file_name) }

      if existing && find_targets_for_file(existing).include?(target_name)
        puts "- Skipped (already exists): #{file_path}"
        skipped += 1
        next
      end

      if existing
        # File exists but not in target, add to target
        if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
          target.source_build_phase.add_file_reference(existing)
        end
        puts "✓ Added to target: #{file_path}"
      else
        group = find_or_create_group_for_file(file_path)
        file_ref = group.new_file(file_name)

        if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
          target.source_build_phase.add_file_reference(file_ref)
        end
        puts "✓ New: #{file_path}"
      end
      added += 1
    end

    @project.save
    puts "\nTotal: #{added} files added" + (skipped > 0 ? ", #{skipped} skipped" : "")
    true
  end

  # Remove file references
  def remove_files(file_names)
    backup
    removed = 0

    file_names.each do |name|
      files_to_remove = []

      @project.files.each do |file|
        file_name = file.path&.split('/')&.last
        if file_name == name || file.path&.end_with?(name)
          files_to_remove << file
        end
      end

      if files_to_remove.empty?
        puts "✗ Not found: #{name}"
      else
        files_to_remove.each do |file|
          puts "✓ Removed: #{file.path}"
          file.remove_from_project
          removed += 1
        end
      end
    end

    if removed > 0
      @project.save
      puts "\nTotal: #{removed} file references removed"
    end
    removed
  end

  # Check project integrity
  def check
    puts "\nProject integrity check:"
    puts "-" * 60

    warnings = []
    errors = []

    # Check if file references exist
    @project.files.each do |file|
      next unless file.path
      next if file.path.start_with?('System/') # Skip system files
      next if file.parent.is_a?(Xcodeproj::Project::Object::PBXVariantGroup) # Skip i18n files

      full_path = build_path_from_group(file)
      if full_path && !File.exist?(full_path)
        errors << "File does not exist: #{file.path} (#{full_path})"
      end
    end

    # Check duplicate references
    paths = @project.files.map(&:path).compact
    duplicates = paths.group_by(&:itself).select { |_, v| v.size > 1 }.keys
    duplicates.each do |path|
      warnings << "Duplicate reference: #{path}"
    end

    # Check empty groups
    check_empty_groups(@project.main_group, warnings)

    # Output results
    if errors.any?
      puts "\n❌ Found #{errors.count} errors:"
      errors.first(20).each { |e| puts "  ✗ #{e}" }
      puts "  ... and #{errors.count - 20} more errors" if errors.count > 20
    end

    if warnings.any?
      puts "\n⚠️  Found #{warnings.count} warnings:"
      warnings.first(10).each { |w| puts "  ! #{w}" }
      puts "  ... and #{warnings.count - 10} more warnings" if warnings.count > 10
    end

    if errors.empty? && warnings.empty?
      puts "✓ Project integrity is good"
    end

    { errors: errors, warnings: warnings }
  end

  # Fix broken references
  def fix
    puts "\nFixing project..."
    backup
    fixed = 0

    # Remove non-existent file references
    files_to_remove = []
    @project.files.each do |file|
      next unless file.path
      next if file.path.start_with?('System/')
      next if file.parent.is_a?(Xcodeproj::Project::Object::PBXVariantGroup) # Skip i18n files

      full_path = build_path_from_group(file)
      if full_path && !File.exist?(full_path)
        files_to_remove << file
      end
    end

    files_to_remove.each do |file|
      puts "✓ Removed non-existent file: #{file.path}"
      file.remove_from_project
      fixed += 1
    end

    # Remove duplicate references
    paths_seen = {}
    @project.files.each do |file|
      next unless file.path
      if paths_seen[file.path]
        puts "✓ Removed duplicate reference: #{file.path}"
        file.remove_from_project
        fixed += 1
      else
        paths_seen[file.path] = true
      end
    end

    if fixed > 0
      @project.save
      puts "\nTotal: #{fixed} issues fixed"
    else
      puts "No issues to fix"
    end
    fixed
  end

  # Smart fix - detect unadded files and auto-add to correct targets
  def smart_fix(dry_run: false)
    puts "\n🔍 Smart fix" + (dry_run ? " (preview mode)" : "") + ":"
    puts "=" * 70

    issues = []
    fixes = []

    # 1. Collect files already in the project
    existing_files = Set.new
    @project.files.each do |file|
      next unless file.path
      # Save both filename and full path forms
      existing_files.add(File.basename(file.path))
      existing_files.add(file.path)
    end

    # 2. Define directory-to-target mapping rules
    target_rules = {
      'DMSAApp' => {
        dirs: ['DMSAApp/DMSAApp'],
        exclude: ['DMSAService', 'DMSAShared'],
        target: 'DMSAApp'
      },
      'DMSAService' => {
        dirs: ['DMSAApp/DMSAService'],
        exclude: ['DMSAApp/DMSAApp', 'DMSAShared'],
        target: 'com.ttttt.dmsa.service'
      },
      'DMSAShared' => {
        dirs: ['DMSAApp/DMSAShared'],
        exclude: [],
        target: nil  # Shared files need to be added to both targets
      }
    }

    # 3. Scan Swift files on disk
    puts "\n📂 Scanning disk files..."
    disk_files = {}

    ['DMSAApp', 'DMSAService', 'DMSAShared'].each do |scan_dir|
      full_dir = File.join(@project_dir, scan_dir)
      next unless Dir.exist?(full_dir)

      Dir.glob("#{full_dir}/**/*.swift").each do |file_path|
        relative_path = file_path.sub("#{@project_dir}/", '')
        file_name = File.basename(file_path)

        # Skip already existing files
        next if existing_files.include?(file_name)
        next if existing_files.include?(relative_path)
        # Skip generated files
        next if file_name.include?('.generated.')
        next if file_name.start_with?('._')

        # Infer target
        target = infer_target(relative_path)
        disk_files[relative_path] = target
      end
    end

    # 4. Report findings
    if disk_files.empty?
      puts "✅ No unadded Swift files found"
    else
      puts "\n📋 Found #{disk_files.count} unadded files:"
      puts "-" * 70

      grouped = disk_files.group_by { |_, target| target }

      grouped.each do |target, files|
        target_name = target.is_a?(Array) ? target.join(' + ') : (target || '(cannot infer)')
        puts "\n  [#{target_name}]"
        files.each do |path, _|
          puts "    + #{path}"
          fixes << { path: path, target: target }
        end
      end
    end

    # 5. Check broken references
    puts "\n🔗 Checking broken references..."
    broken_refs = []
    @project.files.each do |file|
      next unless file.path
      next if file.path.start_with?('System/')
      # Skip product files
      next if file.path.end_with?('.app', '.service')
      # Skip PBXVariantGroup children (i18n localization files, e.g. en.lproj/Localizable.strings)
      next if file.parent.is_a?(Xcodeproj::Project::Object::PBXVariantGroup)

      full_path = build_path_from_group(file)
      if full_path && !File.exist?(full_path)
        broken_refs << { file: file, path: full_path }
      end
    end

    if broken_refs.empty?
      puts "✅ No broken file references"
    else
      puts "\n⚠️  Found #{broken_refs.count} broken references:"
      broken_refs.first(10).each do |ref|
        puts "    ✗ #{ref[:file].path}"
      end
      puts "    ... and #{broken_refs.count - 10} more" if broken_refs.count > 10
    end

    # 6. Check duplicate references (excluding expected DMSAShared duplicates)
    puts "\n🔄 Checking duplicate references..."
    paths = @project.files.map(&:path).compact
    duplicates = paths.group_by(&:itself).select { |_, v| v.size > 1 }

    # Filter out expected DMSAShared duplicates (shared code in both targets)
    unexpected_dups = duplicates.reject do |path, _|
      # Check if it's a shared file (by checking if it's in both targets)
      file_refs = @project.files.select { |f| f.path == path }
      if file_refs.size == 2
        targets = file_refs.flat_map { |f| find_targets_for_file(f) }.uniq
        targets.sort == ['DMSAApp', 'com.ttttt.dmsa.service'].sort
      else
        false
      end
    end

    if unexpected_dups.empty?
      puts "✅ No unexpected duplicate references"
      puts "   (DMSAShared files appearing in both targets is expected behavior)"
    else
      puts "\n⚠️  Found #{unexpected_dups.count} unexpected duplicate references:"
      unexpected_dups.keys.first(10).each do |path|
        puts "    ! #{path} (#{unexpected_dups[path].size} times)"
      end
    end

    # 7. Execute fixes
    if dry_run
      puts "\n" + "=" * 70
      puts "📝 Preview mode - no changes made"
      puts "   Use 'smart-fix' (without --dry-run) to execute fixes"
      return { added: 0, removed: 0, fixed: 0 }
    end

    return { added: 0, removed: 0, fixed: 0 } if fixes.empty? && broken_refs.empty? && unexpected_dups.empty?

    backup
    added = 0
    removed = 0
    fixed = 0

    # Add missing files
    fixes.each do |fix|
      targets = fix[:target].is_a?(Array) ? fix[:target] : [fix[:target]]
      targets.compact.each do |target_name|
        target = @project.targets.find { |t| t.name == target_name }
        next unless target

        file_path = File.join(@project_dir, fix[:path])
        next unless File.exist?(file_path)

        group = find_or_create_group_for_file(fix[:path])
        file_ref = group.new_file(File.basename(fix[:path]))
        target.source_build_phase.add_file_reference(file_ref)
        puts "✓ Added: #{fix[:path]} -> #{target_name}"
        added += 1
      end
    end

    # Remove broken references
    broken_refs.each do |ref|
      ref[:file].remove_from_project
      puts "✓ Removed broken reference: #{ref[:file].path}"
      removed += 1
    end

    # Only remove unexpected duplicate references
    unexpected_dups.keys.each do |path|
      file_refs = @project.files.select { |f| f.path == path }
      # Keep the first, remove the rest
      file_refs[1..].each do |file|
        file.remove_from_project
        puts "✓ Removed unexpected duplicate reference: #{file.path}"
        fixed += 1
      end
    end

    @project.save

    puts "\n" + "=" * 70
    puts "✅ Fix complete:"
    puts "   Added: #{added} files"
    puts "   Removed: #{removed} broken references"
    puts "   Deduped: #{fixed} duplicate references"

    { added: added, removed: removed, fixed: fixed }
  end

  # Show project statistics
  def stats
    puts "\nProject statistics:"
    puts "-" * 60

    # File type statistics
    type_counts = Hash.new(0)
    @project.files.each do |file|
      ext = File.extname(file.path || '').downcase
      ext = '(no extension)' if ext.empty?
      type_counts[ext] += 1
    end

    puts "\nFile type distribution:"
    type_counts.sort_by { |_, count| -count }.each do |ext, count|
      bar = '█' * [count / 2, 30].min
      puts "  #{ext.ljust(15)} #{count.to_s.rjust(4)} #{bar}"
    end

    # Target statistics
    puts "\nTarget source file statistics:"
    @project.targets.each do |target|
      count = target.source_build_phase&.files&.count || 0
      bar = '█' * [count / 5, 30].min
      puts "  #{target.name.ljust(30)} #{count.to_s.rjust(4)} #{bar}"
    end

    puts "-" * 60
    puts "Total files: #{@project.files.count}"
  end

  private

  def find_or_create_group_for_file(file_path)
    # file_path format: DMSAService/Monitor/ServicePowerMonitor.swift
    # Actual disk path: DMSAApp/DMSAService/Monitor/ServicePowerMonitor.swift
    # pbxproj group hierarchy: main_group > DMSAApp > DMSAService > Monitor
    #
    # Scan directories are DMSAApp, DMSAService, DMSAShared (all under DMSAApp/ on disk)
    # So path prefix DMSAService/ maps to DMSAApp > DMSAService two-level groups in pbxproj

    parts = file_path.split('/')
    parts.pop  # Remove filename

    # Build full group path (starting from main_group)
    # DMSAApp/xxx -> group path: ['DMSAApp', 'DMSAApp', ...]  (disk dir and group name happen to be the same)
    # DMSAService/xxx -> group path: ['DMSAApp', 'DMSAService', ...]
    # DMSAShared/xxx -> group path: ['DMSAApp', 'DMSAShared', ...]
    group_parts = if parts[0] == 'DMSAApp'
                    parts  # DMSAApp/App/xxx -> ['DMSAApp', 'App', ...]
                  elsif parts[0] == 'DMSAService' || parts[0] == 'DMSAShared'
                    ['DMSAApp'] + parts  # DMSAService/VFS/xxx -> ['DMSAApp', 'DMSAService', 'VFS', ...]
                  else
                    parts
                  end

    # Traverse or create groups
    current_group = @project.main_group
    group_parts.each do |part|
      child = current_group.children.find do |c|
        c.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
          (c.name == part || c.path == part || c.display_name == part)
      end

      if child
        current_group = child
      else
        current_group = current_group.new_group(part, part)
      end
    end

    current_group
  end

  def build_path_from_group(file_ref)
    # PBXVariantGroup children (i18n files like en.lproj/Localizable.strings) need special handling
    # VariantGroup child's path is "en.lproj/Localizable.strings",
    # parent is PBXVariantGroup (name="Localizable.strings"), grandparent is a regular PBXGroup
    if file_ref.parent.is_a?(Xcodeproj::Project::Object::PBXVariantGroup)
      # Skip VariantGroup layer, build path from VariantGroup's parent group
      parts = [file_ref.path]  # e.g. "en.lproj/Localizable.strings"
      parent = file_ref.parent.parent  # Skip PBXVariantGroup
      while parent && parent.respond_to?(:path) && parent.path
        parts.unshift(parent.path)
        parent = parent.parent
      end
      return File.join(@project_dir, *parts)
    end

    parts = [file_ref.path]
    parent = file_ref.parent

    while parent && parent.respond_to?(:path) && parent.path
      parts.unshift(parent.path)
      parent = parent.parent
    end

    File.join(@project_dir, *parts)
  end

  def find_targets_for_file(file_ref)
    targets = []
    @project.targets.each do |target|
      build_files = target.source_build_phase&.files || []
      if build_files.any? { |bf| bf.file_ref == file_ref }
        targets << target.name
      end
    end
    targets
  end

  def check_empty_groups(group, warnings, path = '')
    return unless group.respond_to?(:children)

    group.children.each do |child|
      if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
        child_path = path.empty? ? child.display_name : "#{path}/#{child.display_name}"
        if child.children.empty?
          warnings << "Empty group: #{child_path}"
        else
          check_empty_groups(child, warnings, child_path)
        end
      end
    end
  end

  def format_size(bytes)
    if bytes < 1024
      "#{bytes} B"
    elsif bytes < 1024 * 1024
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1024.0 / 1024.0).round(1)} MB"
    end
  end

  # Infer target based on file path
  def infer_target(file_path)
    if file_path.start_with?('DMSAApp/')
      'DMSAApp'
    elsif file_path.start_with?('DMSAService/')
      'com.ttttt.dmsa.service'
    elsif file_path.start_with?('DMSAShared/')
      # Shared code needs to be added to both targets
      ['DMSAApp', 'com.ttttt.dmsa.service']
    else
      nil
    end
  end
end

# Main program
def main
  if ARGV.empty?
    puts <<~USAGE
      pbxproj_tool.rb - Xcode project management tool (Ruby version)

      Usage: bundle exec ruby pbxproj_tool.rb <command> [arguments]

      File management:
        list [pattern]              List files (optional filter)
        find <pattern>              Find matching files
        info <filename>             Show file details
        add <file> <target>         Add file to target
        add-multi <target> <files>  Batch add files to target
        remove <file1> [file2...]   Remove file references

      Project management:
        list-targets                List build targets
        check                       Check project integrity
        fix                         Fix broken references
        smart-fix [--dry-run]       Smart fix (auto-detect and add missing files)
        stats                       Show project statistics

      Backup management:
        backup                      Manually backup project file
        list-backups                List all backups
        restore [backup_name]       Restore backup (latest by default)

      Examples:
        ruby pbxproj_tool.rb list swift          # List files containing 'swift'
        ruby pbxproj_tool.rb find ViewModel      # Find ViewModel related files
        ruby pbxproj_tool.rb info StateManager.swift
        ruby pbxproj_tool.rb add DMSAApp/Models/NewModel.swift DMSAApp
        ruby pbxproj_tool.rb add-multi com.ttttt.dmsa.service file1.swift file2.swift
        ruby pbxproj_tool.rb remove OldView.swift
        ruby pbxproj_tool.rb check
        ruby pbxproj_tool.rb fix
        ruby pbxproj_tool.rb smart-fix --dry-run   # Preview mode
        ruby pbxproj_tool.rb smart-fix             # Execute fix
    USAGE
    exit 1
  end

  begin
    tool = PBXProjTool.new
    command = ARGV.shift

    case command
    when 'list'
      tool.list_files(ARGV[0])
    when 'list-targets'
      tool.list_targets
    when 'find'
      pattern = ARGV[0]
      unless pattern
        puts "Usage: find <pattern>"
        exit 1
      end
      tool.find_files(pattern)
    when 'info'
      filename = ARGV[0]
      unless filename
        puts "Usage: info <filename>"
        exit 1
      end
      tool.file_info(filename)
    when 'add'
      file, target = ARGV[0], ARGV[1]
      unless file && target
        puts "Usage: add <file> <target>"
        exit 1
      end
      tool.add_file(file, target)
    when 'add-multi'
      target = ARGV.shift
      files = ARGV
      unless target && files.any?
        puts "Usage: add-multi <target> <file1> [file2...]"
        exit 1
      end
      tool.add_files(files, target)
    when 'remove'
      unless ARGV.any?
        puts "Usage: remove <file1> [file2...]"
        exit 1
      end
      tool.remove_files(ARGV)
    when 'check'
      tool.check
    when 'fix'
      tool.fix
    when 'smart-fix'
      dry_run = ARGV.include?('--dry-run')
      tool.smart_fix(dry_run: dry_run)
    when 'stats'
      tool.stats
    when 'backup'
      tool.backup
    when 'list-backups'
      tool.list_backups
    when 'restore'
      tool.restore(ARGV[0])
    else
      puts "Unknown command: #{command}"
      puts "Use 'ruby pbxproj_tool.rb' to see help"
      exit 1
    end
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
    exit 1
  end
end

main if __FILE__ == $0
