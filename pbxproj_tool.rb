#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# pbxproj 操作工具 (Ruby 版)
# 使用 CocoaPods 的 xcodeproj gem
#
# 使用方法:
#   bundle exec ruby pbxproj_tool.rb <command> [options]
#
# 命令:
#   list [pattern]              列出项目中的所有文件 (可选过滤)
#   list-targets                列出所有构建目标
#   find <pattern>              查找匹配的文件
#   info <filename>             显示文件详细信息
#   add <file> <target>         添加文件到目标
#   add-multi <target> <files>  批量添加文件到目标
#   remove <file1> [file2...]   移除文件引用
#   check                       检查项目完整性
#   fix                         修复损坏的引用
#   smart-fix [--dry-run]       智能修复 (检测未添加的文件并自动添加)
#   backup                      手动备份项目文件
#   restore [backup_name]       恢复备份

# 强制使用 UTF-8 编码
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'xcodeproj'
require 'fileutils'

# 自动检测项目路径
def find_project_path
  candidates = [
    'DMSAApp.xcodeproj',
    'DMSAApp/DMSAApp.xcodeproj',
    '../DMSAApp/DMSAApp.xcodeproj'
  ]

  candidates.each do |path|
    return path if File.exist?(path)
  end

  raise "找不到 DMSAApp.xcodeproj (搜索路径: #{candidates.join(', ')})"
end

PROJECT_PATH = find_project_path
# 备份目录始终在项目根目录
BACKUP_DIR = File.expand_path('../.pbxproj_backups', PROJECT_PATH)

class PBXProjTool
  def initialize
    # 确保读取文件时使用 UTF-8
    @project = Xcodeproj::Project.open(PROJECT_PATH)
    @project_dir = File.dirname(File.expand_path(PROJECT_PATH))
  end

  # 备份项目文件
  def backup
    FileUtils.mkdir_p(BACKUP_DIR)
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_path = File.join(BACKUP_DIR, "project.pbxproj.#{timestamp}")
    FileUtils.cp("#{PROJECT_PATH}/project.pbxproj", backup_path)
    puts "✓ 已备份到: #{backup_path}"
    backup_path
  end

  # 恢复备份
  def restore(backup_name = nil)
    unless Dir.exist?(BACKUP_DIR)
      puts "✗ 备份目录不存在: #{BACKUP_DIR}"
      return false
    end

    backups = Dir.glob("#{BACKUP_DIR}/project.pbxproj.*").sort
    if backups.empty?
      puts "✗ 没有找到备份文件"
      return false
    end

    if backup_name
      backup_path = backups.find { |b| b.include?(backup_name) }
      unless backup_path
        puts "✗ 找不到备份: #{backup_name}"
        puts "可用备份:"
        backups.each { |b| puts "  - #{File.basename(b)}" }
        return false
      end
    else
      # 使用最新备份
      backup_path = backups.last
    end

    # 先备份当前文件
    current_backup = backup
    puts "当前文件已备份到: #{current_backup}"

    # 恢复
    FileUtils.cp(backup_path, "#{PROJECT_PATH}/project.pbxproj")
    puts "✓ 已从 #{File.basename(backup_path)} 恢复"
    true
  end

  # 列出所有备份
  def list_backups
    unless Dir.exist?(BACKUP_DIR)
      puts "没有备份目录"
      return []
    end

    backups = Dir.glob("#{BACKUP_DIR}/project.pbxproj.*").sort
    if backups.empty?
      puts "没有备份文件"
      return []
    end

    puts "\n可用备份:"
    puts "-" * 50
    backups.each do |b|
      size = File.size(b)
      mtime = File.mtime(b)
      puts "  #{File.basename(b)} (#{format_size(size)}, #{mtime.strftime('%Y-%m-%d %H:%M:%S')})"
    end
    puts "-" * 50
    puts "共 #{backups.count} 个备份"
    backups
  end

  # 列出所有文件
  def list_files(pattern = nil)
    puts "\n项目文件列表:"
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
    puts "共 #{count} 个文件" + (pattern ? " (匹配 '#{pattern}')" : "")
  end

  # 列出所有目标
  def list_targets
    puts "\n构建目标:"
    puts "-" * 60

    @project.targets.each do |target|
      type = target.product_type&.split('.')&.last || '?'
      files_count = target.source_build_phase&.files&.count || 0
      puts "  [#{type.ljust(12)}] #{target.name} (#{files_count} 个源文件)"
    end

    puts "-" * 60
    puts "共 #{@project.targets.count} 个目标"
  end

  # 查找文件
  def find_files(pattern)
    puts "\n查找文件: '#{pattern}'"
    puts "-" * 80

    results = []
    @project.files.each do |file|
      next unless file.path
      if file.path.downcase.include?(pattern.downcase)
        results << file
      end
    end

    if results.empty?
      puts "没有找到匹配的文件"
    else
      results.each do |file|
        # 找出包含此文件的目标
        targets = find_targets_for_file(file)
        targets_str = targets.empty? ? "(未加入任何目标)" : targets.join(', ')
        puts "  #{file.path}"
        puts "    -> 目标: #{targets_str}"
      end
      puts "-" * 80
      puts "找到 #{results.count} 个匹配文件"
    end
    results
  end

  # 显示文件详情
  def file_info(filename)
    puts "\n文件信息: '#{filename}'"
    puts "-" * 60

    file = @project.files.find { |f| f.path&.end_with?(filename) }
    unless file
      puts "✗ 未找到文件: #{filename}"
      return nil
    end

    puts "路径:       #{file.path}"
    puts "类型:       #{file.last_known_file_type || file.explicit_file_type || '未知'}"
    puts "源树:       #{file.source_tree}"
    puts "UUID:       #{file.uuid}"

    # 完整路径
    full_path = build_path_from_group(file)
    puts "完整路径:   #{full_path}"
    puts "文件存在:   #{File.exist?(full_path) ? '✓ 是' : '✗ 否'}"

    # 查找包含的目标
    targets = find_targets_for_file(file)
    if targets.any?
      puts "所属目标:   #{targets.join(', ')}"
    else
      puts "所属目标:   (未加入任何目标)"
    end

    # 父组信息
    if file.parent
      puts "父组:       #{file.parent.display_name rescue file.parent.path}"
    end

    puts "-" * 60
    file
  end

  # 添加文件到目标
  def add_file(file_path, target_name)
    unless File.exist?(file_path)
      puts "✗ 文件不存在: #{file_path}"
      return false
    end

    target = @project.targets.find { |t| t.name == target_name }
    unless target
      puts "✗ 目标不存在: #{target_name}"
      puts "可用目标: #{@project.targets.map(&:name).join(', ')}"
      return false
    end

    # 检查是否已存在
    file_name = File.basename(file_path)
    existing = @project.files.find { |f| f.path&.end_with?(file_name) }
    if existing
      puts "! 文件已存在于项目中: #{existing.path}"
      # 检查是否已在目标中
      if find_targets_for_file(existing).include?(target_name)
        puts "  且已在目标 #{target_name} 中"
        return true
      end
      # 添加到目标
      if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
        target.source_build_phase.add_file_reference(existing)
        @project.save
        puts "✓ 已添加到目标: #{target_name}"
        return true
      end
    end

    backup

    # 查找或创建组
    group = find_or_create_group_for_file(file_path)

    # 添加文件引用 - 只用文件名
    file_ref = group.new_file(file_name)

    # 添加到目标的编译源
    if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
      target.source_build_phase.add_file_reference(file_ref)
    end

    @project.save
    puts "✓ 已添加: #{file_path} -> #{target_name}"
    true
  end

  # 批量添加文件
  def add_files(file_paths, target_name)
    target = @project.targets.find { |t| t.name == target_name }
    unless target
      puts "✗ 目标不存在: #{target_name}"
      puts "可用目标: #{@project.targets.map(&:name).join(', ')}"
      return false
    end

    backup
    added = 0
    skipped = 0

    file_paths.each do |file_path|
      unless File.exist?(file_path)
        puts "✗ 文件不存在: #{file_path}"
        next
      end

      file_name = File.basename(file_path)
      existing = @project.files.find { |f| f.path&.end_with?(file_name) }

      if existing && find_targets_for_file(existing).include?(target_name)
        puts "- 跳过 (已存在): #{file_path}"
        skipped += 1
        next
      end

      if existing
        # 文件存在但不在目标中，添加到目标
        if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
          target.source_build_phase.add_file_reference(existing)
        end
        puts "✓ 添加到目标: #{file_path}"
      else
        group = find_or_create_group_for_file(file_path)
        file_ref = group.new_file(file_name)

        if file_path.end_with?('.swift', '.m', '.mm', '.c', '.cpp')
          target.source_build_phase.add_file_reference(file_ref)
        end
        puts "✓ 新增: #{file_path}"
      end
      added += 1
    end

    @project.save
    puts "\n共添加 #{added} 个文件" + (skipped > 0 ? ", 跳过 #{skipped} 个" : "")
    true
  end

  # 移除文件引用
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
        puts "✗ 未找到: #{name}"
      else
        files_to_remove.each do |file|
          puts "✓ 移除: #{file.path}"
          file.remove_from_project
          removed += 1
        end
      end
    end

    if removed > 0
      @project.save
      puts "\n共移除 #{removed} 个文件引用"
    end
    removed
  end

  # 检查项目完整性
  def check
    puts "\n项目完整性检查:"
    puts "-" * 60

    warnings = []
    errors = []

    # 检查文件引用是否存在
    @project.files.each do |file|
      next unless file.path
      next if file.path.start_with?('System/') # 跳过系统文件

      full_path = build_path_from_group(file)
      if full_path && !File.exist?(full_path)
        errors << "文件不存在: #{file.path} (#{full_path})"
      end
    end

    # 检查重复引用
    paths = @project.files.map(&:path).compact
    duplicates = paths.group_by(&:itself).select { |_, v| v.size > 1 }.keys
    duplicates.each do |path|
      warnings << "重复引用: #{path}"
    end

    # 检查空组
    check_empty_groups(@project.main_group, warnings)

    # 输出结果
    if errors.any?
      puts "\n❌ 发现 #{errors.count} 个错误:"
      errors.first(20).each { |e| puts "  ✗ #{e}" }
      puts "  ... 还有 #{errors.count - 20} 个错误" if errors.count > 20
    end

    if warnings.any?
      puts "\n⚠️  发现 #{warnings.count} 个警告:"
      warnings.first(10).each { |w| puts "  ! #{w}" }
      puts "  ... 还有 #{warnings.count - 10} 个警告" if warnings.count > 10
    end

    if errors.empty? && warnings.empty?
      puts "✓ 项目完整性良好"
    end

    { errors: errors, warnings: warnings }
  end

  # 修复损坏的引用
  def fix
    puts "\n修复项目..."
    backup
    fixed = 0

    # 移除不存在的文件引用
    files_to_remove = []
    @project.files.each do |file|
      next unless file.path
      next if file.path.start_with?('System/')

      full_path = build_path_from_group(file)
      if full_path && !File.exist?(full_path)
        files_to_remove << file
      end
    end

    files_to_remove.each do |file|
      puts "✓ 移除不存在的文件: #{file.path}"
      file.remove_from_project
      fixed += 1
    end

    # 移除重复引用
    paths_seen = {}
    @project.files.each do |file|
      next unless file.path
      if paths_seen[file.path]
        puts "✓ 移除重复引用: #{file.path}"
        file.remove_from_project
        fixed += 1
      else
        paths_seen[file.path] = true
      end
    end

    if fixed > 0
      @project.save
      puts "\n共修复 #{fixed} 个问题"
    else
      puts "没有需要修复的问题"
    end
    fixed
  end

  # 智能修复 - 检测未添加的文件并自动添加到正确的目标
  def smart_fix(dry_run: false)
    puts "\n🔍 智能修复" + (dry_run ? " (预览模式)" : "") + ":"
    puts "=" * 70

    issues = []
    fixes = []

    # 1. 收集项目中已有的文件
    existing_files = Set.new
    @project.files.each do |file|
      next unless file.path
      # 保存文件名和完整路径两种形式
      existing_files.add(File.basename(file.path))
      existing_files.add(file.path)
    end

    # 2. 定义目录到目标的映射规则
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
        target: nil  # 共享文件需要同时添加到两个目标
      }
    }

    # 3. 扫描磁盘上的 Swift 文件
    puts "\n📂 扫描磁盘文件..."
    disk_files = {}

    ['DMSAApp', 'DMSAService', 'DMSAShared'].each do |scan_dir|
      full_dir = File.join(@project_dir, scan_dir)
      next unless Dir.exist?(full_dir)

      Dir.glob("#{full_dir}/**/*.swift").each do |file_path|
        relative_path = file_path.sub("#{@project_dir}/", '')
        file_name = File.basename(file_path)

        # 跳过已存在的文件
        next if existing_files.include?(file_name)
        next if existing_files.include?(relative_path)
        # 跳过生成的文件
        next if file_name.include?('.generated.')
        next if file_name.start_with?('._')

        # 推断目标
        target = infer_target(relative_path)
        disk_files[relative_path] = target
      end
    end

    # 4. 报告发现
    if disk_files.empty?
      puts "✅ 没有发现未添加的 Swift 文件"
    else
      puts "\n📋 发现 #{disk_files.count} 个未添加的文件:"
      puts "-" * 70

      grouped = disk_files.group_by { |_, target| target }

      grouped.each do |target, files|
        target_name = target.is_a?(Array) ? target.join(' + ') : (target || '(无法推断)')
        puts "\n  [#{target_name}]"
        files.each do |path, _|
          puts "    + #{path}"
          fixes << { path: path, target: target }
        end
      end
    end

    # 5. 检查损坏的引用
    puts "\n🔗 检查损坏的引用..."
    broken_refs = []
    @project.files.each do |file|
      next unless file.path
      next if file.path.start_with?('System/')
      # 跳过产物文件
      next if file.path.end_with?('.app', '.service')

      full_path = build_path_from_group(file)
      if full_path && !File.exist?(full_path)
        broken_refs << { file: file, path: full_path }
      end
    end

    if broken_refs.empty?
      puts "✅ 没有损坏的文件引用"
    else
      puts "\n⚠️  发现 #{broken_refs.count} 个损坏的引用:"
      broken_refs.first(10).each do |ref|
        puts "    ✗ #{ref[:file].path}"
      end
      puts "    ... 还有 #{broken_refs.count - 10} 个" if broken_refs.count > 10
    end

    # 6. 检查重复引用 (排除 DMSAShared 的预期重复)
    puts "\n🔄 检查重复引用..."
    paths = @project.files.map(&:path).compact
    duplicates = paths.group_by(&:itself).select { |_, v| v.size > 1 }

    # 过滤掉 DMSAShared 的预期重复 (共享代码在两个 target 中)
    unexpected_dups = duplicates.reject do |path, _|
      # 检查是否是共享文件 (通过检查是否同时在两个 target 中)
      file_refs = @project.files.select { |f| f.path == path }
      if file_refs.size == 2
        targets = file_refs.flat_map { |f| find_targets_for_file(f) }.uniq
        targets.sort == ['DMSAApp', 'com.ttttt.dmsa.service'].sort
      else
        false
      end
    end

    if unexpected_dups.empty?
      puts "✅ 没有异常的重复引用"
      puts "   (DMSAShared 共享文件在两个 target 中是预期行为)"
    else
      puts "\n⚠️  发现 #{unexpected_dups.count} 个异常重复引用:"
      unexpected_dups.keys.first(10).each do |path|
        puts "    ! #{path} (#{unexpected_dups[path].size} 次)"
      end
    end

    # 7. 执行修复
    if dry_run
      puts "\n" + "=" * 70
      puts "📝 预览模式 - 未执行任何修改"
      puts "   使用 'smart-fix' (不带 --dry-run) 执行修复"
      return { added: 0, removed: 0, fixed: 0 }
    end

    return { added: 0, removed: 0, fixed: 0 } if fixes.empty? && broken_refs.empty? && unexpected_dups.empty?

    backup
    added = 0
    removed = 0
    fixed = 0

    # 添加缺失的文件
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
        puts "✓ 添加: #{fix[:path]} -> #{target_name}"
        added += 1
      end
    end

    # 移除损坏的引用
    broken_refs.each do |ref|
      ref[:file].remove_from_project
      puts "✓ 移除损坏引用: #{ref[:file].path}"
      removed += 1
    end

    # 只移除异常的重复引用
    unexpected_dups.keys.each do |path|
      file_refs = @project.files.select { |f| f.path == path }
      # 保留第一个，移除其他
      file_refs[1..].each do |file|
        file.remove_from_project
        puts "✓ 移除异常重复引用: #{file.path}"
        fixed += 1
      end
    end

    @project.save

    puts "\n" + "=" * 70
    puts "✅ 修复完成:"
    puts "   添加: #{added} 个文件"
    puts "   移除: #{removed} 个损坏引用"
    puts "   去重: #{fixed} 个重复引用"

    { added: added, removed: removed, fixed: fixed }
  end

  # 显示项目统计
  def stats
    puts "\n项目统计:"
    puts "-" * 60

    # 文件类型统计
    type_counts = Hash.new(0)
    @project.files.each do |file|
      ext = File.extname(file.path || '').downcase
      ext = '(无扩展名)' if ext.empty?
      type_counts[ext] += 1
    end

    puts "\n文件类型分布:"
    type_counts.sort_by { |_, count| -count }.each do |ext, count|
      bar = '█' * [count / 2, 30].min
      puts "  #{ext.ljust(15)} #{count.to_s.rjust(4)} #{bar}"
    end

    # 目标统计
    puts "\n目标源文件统计:"
    @project.targets.each do |target|
      count = target.source_build_phase&.files&.count || 0
      bar = '█' * [count / 5, 30].min
      puts "  #{target.name.ljust(30)} #{count.to_s.rjust(4)} #{bar}"
    end

    puts "-" * 60
    puts "总文件数: #{@project.files.count}"
  end

  private

  def find_or_create_group_for_file(file_path)
    # 从文件路径推断组结构
    parts = file_path.split('/')

    # 移除开头的 DMSAApp 或 DMSAService
    if parts[0] == 'DMSAApp' || parts[0] == 'DMSAService' || parts[0] == 'DMSAShared'
      parts = parts[1..]
    end

    # 移除文件名
    parts.pop

    # 遍历或创建组
    current_group = @project.main_group
    parts.each do |part|
      child = current_group.children.find { |c| c.respond_to?(:name) && c.name == part }
      child ||= current_group.children.find { |c| c.respond_to?(:path) && c.path == part }

      if child && child.is_a?(Xcodeproj::Project::Object::PBXGroup)
        current_group = child
      else
        current_group = current_group.new_group(part, part)
      end
    end

    current_group
  end

  def build_path_from_group(file_ref)
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
          warnings << "空组: #{child_path}"
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

  # 根据文件路径推断目标
  def infer_target(file_path)
    if file_path.start_with?('DMSAApp/')
      'DMSAApp'
    elsif file_path.start_with?('DMSAService/')
      'com.ttttt.dmsa.service'
    elsif file_path.start_with?('DMSAShared/')
      # 共享代码需要添加到两个目标
      ['DMSAApp', 'com.ttttt.dmsa.service']
    else
      nil
    end
  end
end

# 主程序
def main
  if ARGV.empty?
    puts <<~USAGE
      pbxproj_tool.rb - Xcode 项目管理工具 (Ruby 版)

      用法: bundle exec ruby pbxproj_tool.rb <命令> [参数]

      文件管理:
        list [pattern]              列出文件 (可选过滤)
        find <pattern>              查找匹配的文件
        info <filename>             显示文件详细信息
        add <file> <target>         添加文件到目标
        add-multi <target> <files>  批量添加文件到目标
        remove <file1> [file2...]   移除文件引用

      项目管理:
        list-targets                列出构建目标
        check                       检查项目完整性
        fix                         修复损坏的引用
        smart-fix [--dry-run]       智能修复 (自动检测并添加缺失文件)
        stats                       显示项目统计

      备份管理:
        backup                      手动备份项目文件
        list-backups                列出所有备份
        restore [backup_name]       恢复备份 (默认最新)

      示例:
        ruby pbxproj_tool.rb list swift          # 列出包含 'swift' 的文件
        ruby pbxproj_tool.rb find ViewModel      # 查找 ViewModel 相关文件
        ruby pbxproj_tool.rb info StateManager.swift
        ruby pbxproj_tool.rb add DMSAApp/Models/NewModel.swift DMSAApp
        ruby pbxproj_tool.rb add-multi com.ttttt.dmsa.service file1.swift file2.swift
        ruby pbxproj_tool.rb remove OldView.swift
        ruby pbxproj_tool.rb check
        ruby pbxproj_tool.rb fix
        ruby pbxproj_tool.rb smart-fix --dry-run   # 预览模式
        ruby pbxproj_tool.rb smart-fix             # 执行修复
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
        puts "用法: find <pattern>"
        exit 1
      end
      tool.find_files(pattern)
    when 'info'
      filename = ARGV[0]
      unless filename
        puts "用法: info <filename>"
        exit 1
      end
      tool.file_info(filename)
    when 'add'
      file, target = ARGV[0], ARGV[1]
      unless file && target
        puts "用法: add <file> <target>"
        exit 1
      end
      tool.add_file(file, target)
    when 'add-multi'
      target = ARGV.shift
      files = ARGV
      unless target && files.any?
        puts "用法: add-multi <target> <file1> [file2...]"
        exit 1
      end
      tool.add_files(files, target)
    when 'remove'
      unless ARGV.any?
        puts "用法: remove <file1> [file2...]"
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
      puts "未知命令: #{command}"
      puts "使用 'ruby pbxproj_tool.rb' 查看帮助"
      exit 1
    end
  rescue StandardError => e
    puts "错误: #{e.message}"
    puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
    exit 1
  end
end

main if __FILE__ == $0
