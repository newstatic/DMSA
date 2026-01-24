#!/usr/bin/env ruby
# encoding: utf-8
#
# 更新 Xcode 项目配置脚本
# 将旧的三个服务 (VFS, Sync, Helper) 替换为统一的 DMSAService
#
# 使用方法:
#   gem install xcodeproj  # 如果尚未安装
#   ruby update_xcode_project.rb
#

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH = '/Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp/DMSAApp.xcodeproj'
SERVICE_DIR = '/Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp/DMSAService'

puts "=== DMSA 项目配置更新脚本 ==="
puts ""

# 打开项目
project = Xcodeproj::Project.open(PROJECT_PATH)
puts "✓ 已打开项目: #{PROJECT_PATH}"

# 获取主应用 target
main_target = project.targets.find { |t| t.name == 'DMSAApp' || t.name == 'DMSA' }
unless main_target
  puts "✗ 找不到主应用 target"
  exit 1
end
puts "✓ 找到主应用 target: #{main_target.name}"

# 查找并记录旧服务 targets
old_targets = {
  vfs: project.targets.find { |t| t.name == 'com.ttttt.dmsa.vfs' },
  sync: project.targets.find { |t| t.name == 'com.ttttt.dmsa.sync' },
  helper: project.targets.find { |t| t.name == 'com.ttttt.dmsa.helper' }
}

puts ""
puts "=== 旧服务 Targets ==="
old_targets.each do |key, target|
  if target
    puts "  #{key}: #{target.name} (将被移除)"
  else
    puts "  #{key}: 未找到"
  end
end

# 创建新的 DMSAService target
puts ""
puts "=== 创建 DMSAService Target ==="

# 检查是否已存在
existing_service = project.targets.find { |t| t.name == 'com.ttttt.dmsa.service' }
if existing_service
  puts "! DMSAService target 已存在，跳过创建"
  service_target = existing_service
else
  # 创建新 target
  service_target = project.new_target(:command_line_tool, 'com.ttttt.dmsa.service', :osx)
  service_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.ttttt.dmsa.service'
    config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = ''
    config.build_settings['INFOPLIST_FILE'] = 'DMSAService/Resources/Info.plist'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'DMSAService/Resources/DMSAService.entitlements'

    # macFUSE Framework 搜索路径
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '/Library/Frameworks']
    config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '/Library/Frameworks']
  end
  puts "✓ 创建 DMSAService target"
end

# 创建 DMSAService 文件组
puts ""
puts "=== 添加 DMSAService 文件组 ==="

# 查找或创建 DMSAService 组
service_group = project.main_group.find_subpath('DMSAService', true)
unless service_group
  service_group = project.main_group.new_group('DMSAService', 'DMSAService')
end

# 定义要添加的文件
service_files = [
  'main.swift',
  'ServiceDelegate.swift',
  'ServiceImplementation.swift',
  'VFS/VFSManager.swift',
  'VFS/VFSFileSystem.swift',
  'Sync/SyncManager.swift',
  'Privileged/PrivilegedOperations.swift',
  'Resources/Info.plist',
  'Resources/DMSAService.entitlements',
  'Resources/com.ttttt.dmsa.service.plist'
]

# 添加源文件到 target
service_files.each do |file_path|
  full_path = File.join(SERVICE_DIR, file_path)

  unless File.exist?(full_path)
    puts "  ! 文件不存在: #{file_path}"
    next
  end

  # 创建子目录组
  dir_parts = File.dirname(file_path).split('/')
  current_group = service_group

  dir_parts.each do |part|
    next if part == '.'
    child = current_group.children.find { |c| c.display_name == part }
    unless child
      child = current_group.new_group(part, part)
    end
    current_group = child
  end

  # 检查文件是否已添加
  file_name = File.basename(file_path)
  existing = current_group.children.find { |c| c.display_name == file_name }

  if existing
    puts "  - #{file_path} (已存在)"
  else
    file_ref = current_group.new_file(full_path)

    # 添加到编译源
    if file_path.end_with?('.swift')
      service_target.source_build_phase.add_file_reference(file_ref)
      puts "  + #{file_path} (已添加到编译源)"
    else
      puts "  + #{file_path} (已添加为资源)"
    end
  end
end

# 添加 DMSAShared 文件到 DMSAService target
puts ""
puts "=== 添加 DMSAShared 文件到 DMSAService ==="

shared_group = project.main_group.find_subpath('DMSAShared', false)
if shared_group
  def add_files_recursive(group, target)
    group.children.each do |child|
      if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
        add_files_recursive(child, target)
      elsif child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
        if child.path&.end_with?('.swift')
          # 检查是否已添加
          already_added = target.source_build_phase.files.any? do |f|
            f.file_ref&.uuid == child.uuid
          end

          unless already_added
            target.source_build_phase.add_file_reference(child)
            puts "  + #{child.path}"
          end
        end
      end
    end
  end

  add_files_recursive(shared_group, service_target)
else
  puts "  ! DMSAShared 组未找到"
end

# 添加 DMSAServiceProtocol.swift
puts ""
puts "=== 添加 DMSAServiceProtocol ==="

protocol_path = File.join(SERVICE_DIR, '../DMSAShared/Protocols/DMSAServiceProtocol.swift')
if File.exist?(protocol_path)
  protocols_group = shared_group&.find_subpath('Protocols', false)
  if protocols_group
    existing_protocol = protocols_group.children.find { |c| c.display_name == 'DMSAServiceProtocol.swift' }
    unless existing_protocol
      protocol_ref = protocols_group.new_file(protocol_path)
      service_target.source_build_phase.add_file_reference(protocol_ref)
      main_target.source_build_phase.add_file_reference(protocol_ref)
      puts "✓ 已添加 DMSAServiceProtocol.swift"
    else
      puts "- DMSAServiceProtocol.swift 已存在"
    end
  end
end

# 添加 ServiceClient.swift 到主应用
puts ""
puts "=== 添加 ServiceClient 到主应用 ==="

service_client_path = '/Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp/DMSAApp/Services/ServiceClient.swift'
if File.exist?(service_client_path)
  services_group = project.main_group.find_subpath('DMSAApp/Services', false)
  if services_group
    existing_client = services_group.children.find { |c| c.display_name == 'ServiceClient.swift' }
    unless existing_client
      client_ref = services_group.new_file(service_client_path)
      main_target.source_build_phase.add_file_reference(client_ref)
      puts "✓ 已添加 ServiceClient.swift"
    else
      puts "- ServiceClient.swift 已存在"
    end
  end
end

# 更新主应用的依赖
puts ""
puts "=== 更新依赖关系 ==="

# 移除旧的依赖
main_target.dependencies.dup.each do |dep|
  if dep.target && ['com.ttttt.dmsa.vfs', 'com.ttttt.dmsa.sync', 'com.ttttt.dmsa.helper'].include?(dep.target.name)
    main_target.dependencies.delete(dep)
    puts "  - 移除依赖: #{dep.target.name}"
  end
end

# 添加新依赖
unless main_target.dependencies.any? { |d| d.target&.name == 'com.ttttt.dmsa.service' }
  main_target.add_dependency(service_target)
  puts "  + 添加依赖: com.ttttt.dmsa.service"
end

# 更新 Copy Files Build Phase
puts ""
puts "=== 更新 Copy Files Phase ==="

# 查找或创建 Copy Service build phase
copy_service_phase = main_target.build_phases.find do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
  phase.name == 'Copy Service'
end

unless copy_service_phase
  copy_service_phase = main_target.new_copy_files_build_phase('Copy Service')
  copy_service_phase.dst_subfolder_spec = '1'  # Wrapper
  copy_service_phase.dst_path = 'Contents/Library/LaunchServices'
end

# 清除旧的 copy files
copy_service_phase.files.dup.each do |file|
  if file.file_ref && ['com.ttttt.dmsa.vfs', 'com.ttttt.dmsa.sync', 'com.ttttt.dmsa.helper'].any? { |n| file.file_ref.path&.include?(n) }
    copy_service_phase.files.delete(file)
    puts "  - 移除: #{file.file_ref.path}"
  end
end

# 添加新服务
service_product = service_target.product_reference
unless copy_service_phase.files.any? { |f| f.file_ref&.uuid == service_product.uuid }
  copy_service_phase.add_file_reference(service_product, true)
  puts "  + 添加: com.ttttt.dmsa.service"
end

# 移除旧的 Copy Phases
['Copy VFS Service', 'Copy Sync Service', 'Copy Helper to LaunchServices'].each do |phase_name|
  old_phase = main_target.build_phases.find do |phase|
    phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && phase.name == phase_name
  end
  if old_phase
    main_target.build_phases.delete(old_phase)
    puts "  - 移除 Build Phase: #{phase_name}"
  end
end

# 保存项目
puts ""
puts "=== 保存项目 ==="
project.save
puts "✓ 项目已保存"

puts ""
puts "=== 完成 ==="
puts ""
puts "后续步骤:"
puts "1. 在 Xcode 中打开项目"
puts "2. 检查 DMSAService target 配置"
puts "3. 编译验证"
puts ""
puts "注意: 旧的服务 targets 仍保留在项目中，"
puts "      确认新配置正常后可手动删除。"
