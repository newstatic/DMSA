#!/usr/bin/env python3
"""
pbxproj 操作工具
用于管理 Xcode 项目文件 (project.pbxproj)

使用方法:
    # 激活虚拟环境
    source .venv/bin/activate

    # 运行脚本
    python pbxproj_tool.py <command> [options]

命令:
    list [pattern]              列出项目中的所有文件 (可选过滤)
    list-groups                 列出项目的组结构
    list-targets                列出所有构建目标
    add <file> [target] [group] 添加文件到项目
    remove <file1> [file2...]   移除指定文件引用
    find <pattern>              查找文件 (支持通配符)
    info <file>                 显示文件详细信息
    check                       检查项目完整性
    fix                         修复损坏的引用
    backup                      备份项目文件
    restore [name]              从备份恢复
    cleanup                     清理预定义的已删除文件

示例:
    python pbxproj_tool.py list
    python pbxproj_tool.py list Settings
    python pbxproj_tool.py list-targets
    python pbxproj_tool.py add NewFile.swift DMSAApp UI/Views
    python pbxproj_tool.py remove OldFile.swift
    python pbxproj_tool.py find "*.swift"
    python pbxproj_tool.py check
    python pbxproj_tool.py fix
"""

import sys
import os
import shutil
import fnmatch
from datetime import datetime
from pathlib import Path

try:
    from pbxproj import XcodeProject
    from pbxproj.pbxextensions import FileOptions
except ImportError:
    print("错误: 请先安装 pbxproj")
    print("运行: source .venv/bin/activate && pip install pbxproj")
    sys.exit(1)

# 项目路径配置
PROJECT_PATH = "DMSAApp/DMSAApp.xcodeproj/project.pbxproj"
BACKUP_DIR = ".pbxproj_backups"


class PBXProjTool:
    """Xcode 项目文件操作工具"""

    def __init__(self, project_path=None):
        self.project_path = project_path or PROJECT_PATH
        self._project = None

    @property
    def project(self):
        """延迟加载项目"""
        if self._project is None:
            if not os.path.exists(self.project_path):
                raise FileNotFoundError(f"找不到项目文件: {self.project_path}")
            self._project = XcodeProject.load(self.project_path)
        return self._project

    def reload(self):
        """重新加载项目"""
        self._project = None
        return self.project

    # ==================== 备份与恢复 ====================

    def backup(self) -> str:
        """备份项目文件"""
        if not os.path.exists(BACKUP_DIR):
            os.makedirs(BACKUP_DIR)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = os.path.join(BACKUP_DIR, f"project.pbxproj.{timestamp}")
        shutil.copy(self.project_path, backup_path)
        print(f"✓ 已备份到: {backup_path}")
        return backup_path

    def restore(self, backup_name=None) -> bool:
        """从备份恢复"""
        if not os.path.exists(BACKUP_DIR):
            print("✗ 错误: 没有找到备份目录")
            return False

        backups = sorted(os.listdir(BACKUP_DIR), reverse=True)
        if not backups:
            print("✗ 错误: 没有可用的备份")
            return False

        if backup_name:
            backup_path = os.path.join(BACKUP_DIR, backup_name)
        else:
            backup_path = os.path.join(BACKUP_DIR, backups[0])
            print(f"使用最新备份: {backups[0]}")

        if not os.path.exists(backup_path):
            print(f"✗ 错误: 备份文件不存在 {backup_path}")
            return False

        shutil.copy(backup_path, self.project_path)
        print(f"✓ 已从备份恢复: {backup_path}")
        self._project = None  # 清除缓存
        return True

    def list_backups(self):
        """列出所有备份"""
        if not os.path.exists(BACKUP_DIR):
            print("没有备份")
            return []

        backups = sorted(os.listdir(BACKUP_DIR), reverse=True)
        if not backups:
            print("没有备份")
            return []

        print("\n可用备份:")
        print("-" * 50)
        for b in backups:
            path = os.path.join(BACKUP_DIR, b)
            size = os.path.getsize(path) / 1024
            print(f"  {b}  ({size:.1f} KB)")
        return backups

    # ==================== 文件列表 ====================

    def list_files(self, pattern=None, file_type=None):
        """列出项目中的文件"""
        files = []
        for ref in self.project.objects.get_objects_in_section('PBXFileReference'):
            name = getattr(ref, 'name', None) or getattr(ref, 'path', 'Unknown')
            path = getattr(ref, 'path', '')
            ftype = getattr(ref, 'lastKnownFileType', '') or getattr(ref, 'explicitFileType', '')

            # 过滤
            if pattern and pattern.lower() not in name.lower():
                continue
            if file_type and file_type not in ftype:
                continue

            files.append({
                'name': name,
                'path': path,
                'type': ftype,
                'id': ref.get_id()
            })

        files.sort(key=lambda x: x['name'].lower())
        return files

    def print_files(self, pattern=None, file_type=None):
        """打印文件列表"""
        files = self.list_files(pattern, file_type)

        print(f"\n项目文件列表" + (f" (过滤: {pattern})" if pattern else "") + ":")
        print("-" * 70)

        for f in files:
            type_short = f['type'].split('.')[-1] if f['type'] else '?'
            print(f"  [{type_short:8}] {f['name']}")

        print("-" * 70)
        print(f"共 {len(files)} 个文件")

        # 检查警告
        warnings = self._check_warnings()
        if warnings:
            print(f"\n⚠️  警告: 项目包含 {len(warnings)} 个问题引用")

    def list_swift_files(self):
        """列出所有 Swift 文件"""
        return self.list_files(file_type='swift')

    # ==================== 组结构 ====================

    def list_groups(self, indent=0, group_id=None):
        """列出项目的组结构"""
        if group_id is None:
            # 从根组开始
            root = self.project.objects.get_objects_in_section('PBXProject')[0]
            main_group = root.mainGroup
            print("\n项目组结构:")
            print("-" * 50)
            self._print_group(main_group, indent=0)
        else:
            group = self.project.objects[group_id]
            self._print_group(group, indent)

    def _print_group(self, group_id, indent=0):
        """递归打印组结构"""
        try:
            group = self.project.objects[group_id]
        except (KeyError, TypeError):
            return

        name = getattr(group, 'name', None) or getattr(group, 'path', '(unnamed)')
        print("  " * indent + f"📁 {name}")

        children = getattr(group, 'children', [])
        for child_id in children:
            try:
                child = self.project.objects[child_id]
                if hasattr(child, 'isa'):
                    if child.isa == 'PBXGroup' or child.isa == 'PBXVariantGroup':
                        self._print_group(child_id, indent + 1)
                    elif child.isa == 'PBXFileReference':
                        name = getattr(child, 'name', None) or getattr(child, 'path', '?')
                        print("  " * (indent + 1) + f"📄 {name}")
            except (KeyError, TypeError):
                continue

    # ==================== 目标管理 ====================

    def list_targets(self):
        """列出所有构建目标"""
        targets = []
        for target in self.project.objects.get_objects_in_section('PBXNativeTarget'):
            name = getattr(target, 'name', 'Unknown')
            product_type = getattr(target, 'productType', '')
            targets.append({
                'name': name,
                'type': product_type,
                'id': target.get_id()
            })

        print("\n构建目标:")
        print("-" * 50)
        for t in targets:
            type_short = t['type'].split('.')[-1] if t['type'] else '?'
            print(f"  [{type_short}] {t['name']}")
        print(f"\n共 {len(targets)} 个目标")
        return targets

    def get_target_by_name(self, name):
        """根据名称获取目标"""
        for target in self.project.objects.get_objects_in_section('PBXNativeTarget'):
            if getattr(target, 'name', '') == name:
                return target
        return None

    # ==================== 文件操作 ====================

    def add_file(self, file_path, target_name=None, group_path=None, create_groups=True):
        """添加文件到项目"""
        if not os.path.exists(file_path):
            print(f"✗ 错误: 文件不存在 {file_path}")
            return False

        self.backup()

        try:
            # 获取目标
            target_name = target_name or self._get_default_target()

            # 添加文件
            options = FileOptions(create_build_files=True)
            files = self.project.add_file(
                file_path,
                parent=self._get_or_create_group(group_path) if group_path else None,
                target_name=target_name,
                file_options=options
            )

            if files:
                self.project.save()
                print(f"✓ 已添加: {file_path} -> {target_name}")
                return True
            else:
                print(f"✗ 添加失败: {file_path}")
                return False

        except Exception as e:
            print(f"✗ 错误: {e}")
            return False

    def add_files(self, file_paths, target_name=None, group_path=None):
        """批量添加文件"""
        self.backup()
        added = []
        failed = []

        target_name = target_name or self._get_default_target()

        for file_path in file_paths:
            if not os.path.exists(file_path):
                failed.append((file_path, "文件不存在"))
                continue

            try:
                options = FileOptions(create_build_files=True)
                files = self.project.add_file(
                    file_path,
                    parent=self._get_or_create_group(group_path) if group_path else None,
                    target_name=target_name,
                    file_options=options
                )
                if files:
                    added.append(file_path)
                    print(f"✓ 已添加: {file_path}")
                else:
                    failed.append((file_path, "添加失败"))
            except Exception as e:
                failed.append((file_path, str(e)))

        if added:
            self.project.save()
            print(f"\n共添加 {len(added)} 个文件")

        if failed:
            print(f"\n{len(failed)} 个文件添加失败:")
            for f, reason in failed:
                print(f"  ✗ {f}: {reason}")

        return added, failed

    def remove_file(self, file_name):
        """移除文件引用"""
        try:
            files = self.project.get_files_by_name(file_name)
            if not files:
                return False

            for f in files:
                self.project.remove_file_by_id(f.get_id())
            return True
        except Exception as e:
            print(f"✗ 移除失败 {file_name}: {e}")
            return False

    def remove_files(self, file_names, save=True):
        """批量移除文件引用"""
        self.backup()

        removed = []
        not_found = []

        for file_name in file_names:
            if self.remove_file(file_name):
                removed.append(file_name)
                print(f"✓ 已移除: {file_name}")
            else:
                not_found.append(file_name)

        if removed and save:
            self.project.save()
            print(f"\n共移除 {len(removed)} 个文件引用")

        if not_found:
            print(f"\n未找到 {len(not_found)} 个文件:")
            for f in not_found:
                print(f"  - {f}")

        return removed, not_found

    def find_files(self, pattern):
        """查找文件 (支持通配符)"""
        files = self.list_files()
        matched = []

        for f in files:
            if fnmatch.fnmatch(f['name'], pattern) or fnmatch.fnmatch(f['path'], pattern):
                matched.append(f)

        print(f"\n查找: {pattern}")
        print("-" * 50)
        for f in matched:
            print(f"  {f['name']} ({f['path']})")
        print(f"\n找到 {len(matched)} 个匹配")
        return matched

    def file_info(self, file_name):
        """显示文件详细信息"""
        files = self.project.get_files_by_name(file_name)
        if not files:
            print(f"未找到文件: {file_name}")
            return None

        for f in files:
            print(f"\n文件信息: {file_name}")
            print("-" * 50)
            print(f"  ID: {f.get_id()}")
            print(f"  名称: {getattr(f, 'name', 'N/A')}")
            print(f"  路径: {getattr(f, 'path', 'N/A')}")
            print(f"  类型: {getattr(f, 'lastKnownFileType', 'N/A')}")
            print(f"  源树: {getattr(f, 'sourceTree', 'N/A')}")

            # 查找所在的构建阶段
            for bp in self.project.objects.get_objects_in_section('PBXBuildFile'):
                file_ref = getattr(bp, 'fileRef', None)
                if file_ref == f.get_id():
                    print(f"  构建文件ID: {bp.get_id()}")

        return files[0] if files else None

    # ==================== 项目检查与修复 ====================

    def check(self):
        """检查项目完整性"""
        print("\n项目完整性检查:")
        print("-" * 50)

        warnings = self._check_warnings()
        errors = []

        # 检查损坏的文件引用
        broken_refs = self._find_broken_references()
        if broken_refs:
            errors.extend(broken_refs)

        # 检查重复的文件引用
        duplicates = self._find_duplicates()
        if duplicates:
            warnings.extend([(f, "重复引用") for f in duplicates])

        # 检查孤立的构建文件
        orphans = self._find_orphan_build_files()
        if orphans:
            warnings.extend([(f, "孤立的构建文件") for f in orphans])

        if errors:
            print(f"\n❌ 发现 {len(errors)} 个错误:")
            for item, reason in errors:
                print(f"  ✗ {item}: {reason}")

        if warnings:
            print(f"\n⚠️  发现 {len(warnings)} 个警告:")
            for item, reason in warnings:
                print(f"  ! {item}: {reason}")

        if not errors and not warnings:
            print("✓ 项目完整性良好")

        return errors, warnings

    def fix(self):
        """修复损坏的引用"""
        print("\n修复项目...")
        self.backup()

        fixed = 0

        # 移除损坏的构建文件引用
        broken_refs = self._find_broken_references()
        for ref_id, reason in broken_refs:
            try:
                # 直接从 objects 中删除损坏的 PBXBuildFile
                if ref_id in self.project.objects:
                    del self.project.objects[ref_id]
                    print(f"✓ 已移除损坏引用: {ref_id}")
                    fixed += 1
                else:
                    print(f"! 引用已不存在: {ref_id}")
            except Exception as e:
                print(f"✗ 修复失败: {ref_id} - {e}")

        if fixed:
            self.project.save()
            self._project = None  # 重新加载
            print(f"\n共修复 {fixed} 个问题")
        else:
            print("没有需要修复的问题")

        return fixed

    def _check_warnings(self):
        """检查警告"""
        warnings = []
        # 这里可以添加更多检查逻辑
        return warnings

    def _find_broken_references(self):
        """查找损坏的文件引用"""
        broken = []
        # 查找引用了不存在对象的情况
        for bp in self.project.objects.get_objects_in_section('PBXBuildFile'):
            file_ref = getattr(bp, 'fileRef', None)
            if file_ref and file_ref not in self.project.objects:
                broken.append((bp.get_id(), f"引用了不存在的文件: {file_ref}"))
        return broken

    def _find_duplicates(self):
        """查找重复的文件引用"""
        seen = {}
        duplicates = []
        for ref in self.project.objects.get_objects_in_section('PBXFileReference'):
            path = getattr(ref, 'path', '')
            if path in seen:
                duplicates.append(path)
            else:
                seen[path] = ref.get_id()
        return duplicates

    def _find_orphan_build_files(self):
        """查找孤立的构建文件"""
        orphans = []
        # 实现孤立构建文件检测
        return orphans

    # ==================== 辅助方法 ====================

    def _get_default_target(self):
        """获取默认目标名称"""
        targets = self.list_targets()
        if targets:
            # 优先选择 App 目标
            for t in targets:
                if 'application' in t['type']:
                    return t['name']
            return targets[0]['name']
        return None

    def _get_or_create_group(self, group_path):
        """获取或创建组"""
        if not group_path:
            return None

        # 简单实现: 返回根组
        # 完整实现需要递归查找/创建组
        root = self.project.objects.get_objects_in_section('PBXProject')[0]
        return root.mainGroup

    # ==================== 预定义清理 ====================

    def cleanup_deleted_ui_files(self):
        """清理已删除的 UI 文件引用"""
        files_to_remove = [
            "GeneralSettingsView.swift",
            "NotificationSettingsView.swift",
            "FilterSettingsView.swift",
            "AdvancedSettingsView.swift",
            "SyncPairSettingsView.swift",
            "VFSSettingsView.swift",
            "SettingsView.swift",
            "DiskSettingsView.swift",
            "StatisticsView.swift",
            "HistoryView.swift",
            "HistoryContentView.swift",
            "NotificationHistoryView.swift",
            "SyncProgressView.swift",
            "WizardView.swift",
        ]

        print("清理已删除的 UI 文件引用...")
        print("=" * 60)
        return self.remove_files(files_to_remove)


# ==================== CLI 入口 ====================

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    tool = PBXProjTool()
    command = sys.argv[1].lower()

    try:
        if command == "list":
            pattern = sys.argv[2] if len(sys.argv) > 2 else None
            tool.print_files(pattern)

        elif command == "list-groups":
            tool.list_groups()

        elif command == "list-targets":
            tool.list_targets()

        elif command == "list-swift":
            files = tool.list_swift_files()
            print(f"\nSwift 文件 ({len(files)} 个):")
            for f in files:
                print(f"  {f['name']}")

        elif command == "add":
            if len(sys.argv) < 3:
                print("用法: add <file> [target] [group]")
                return
            file_path = sys.argv[2]
            target = sys.argv[3] if len(sys.argv) > 3 else None
            group = sys.argv[4] if len(sys.argv) > 4 else None
            tool.add_file(file_path, target, group)

        elif command == "remove":
            if len(sys.argv) < 3:
                print("用法: remove <file1> [file2...]")
                return
            tool.remove_files(sys.argv[2:])

        elif command == "find":
            if len(sys.argv) < 3:
                print("用法: find <pattern>")
                return
            tool.find_files(sys.argv[2])

        elif command == "info":
            if len(sys.argv) < 3:
                print("用法: info <file>")
                return
            tool.file_info(sys.argv[2])

        elif command == "check":
            tool.check()

        elif command == "fix":
            tool.fix()

        elif command == "backup":
            tool.backup()

        elif command == "restore":
            backup_name = sys.argv[2] if len(sys.argv) > 2 else None
            tool.restore(backup_name)

        elif command == "list-backups":
            tool.list_backups()

        elif command == "cleanup":
            tool.cleanup_deleted_ui_files()

        elif command in ["help", "-h", "--help"]:
            print(__doc__)

        else:
            print(f"未知命令: {command}")
            print("运行 'python pbxproj_tool.py help' 查看帮助")

    except FileNotFoundError as e:
        print(f"错误: {e}")
    except Exception as e:
        print(f"错误: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
