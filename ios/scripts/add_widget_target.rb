require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __FILE__)
project = Xcodeproj::Project.open(project_path)

widget_target_name = 'LoveraWidgets'
widget_bundle_id = 'com.lovera.app.lovera.widgets'
ios_deployment_target = '15.0'

# 1. Remove existing target if already present
existing = project.targets.find { |t| t.name == widget_target_name }
if existing
  puts "Target #{widget_target_name} already exists, skipping creation."
  exit 0
end

# 2. Create Widget Extension Native Target
widget_target = project.new_target(:app_extension, widget_target_name, :ios, ios_deployment_target)

# 3. Create PBXGroup for LoveraWidgets and add source & plist files
widget_group = project.main_group.find_subpath(widget_target_name, true)
widget_group.set_source_tree('<group>')
widget_group.set_path(widget_target_name)

swift_file_ref = widget_group.new_file('LoveraWidgetsBundle.swift')
info_plist_ref = widget_group.new_file('Info.plist')
entitlements_ref = widget_group.new_file('LoveraWidgets.entitlements')

# Add Swift source file to Sources build phase of widget_target
widget_target.source_build_phase.add_file_reference(swift_file_ref, true)

# Add System Frameworks (WidgetKit, SwiftUI) to Frameworks build phase
['WidgetKit', 'SwiftUI'].each do |fw_name|
  fw_ref = project.frameworks_group.new_file("System/Library/Frameworks/#{fw_name}.framework")
  fw_ref.name = "#{fw_name}.framework"
  fw_ref.source_tree = 'SDKROOT'
  widget_target.frameworks_build_phase.add_file_reference(fw_ref, true)
end

# 4. Configure Build Settings for LoveraWidgets Target
widget_target.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = widget_bundle_id
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE'] = 'LoveraWidgets/Info.plist'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'LoveraWidgets/LoveraWidgets.entitlements'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = ios_deployment_target
  bs['SWIFT_VERSION'] = '5.0'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['SKIP_INSTALL'] = 'YES'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  bs['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  bs['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bs['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = 'WidgetBackground'
  bs['CLANG_ENABLE_MODULES'] = 'YES'
  bs['SWIFT_OPTIMIZATION_LEVEL'] = config.name == 'Debug' ? '-Onone' : '-O'
end

# 5. Configure Runner Target to depend on and embed LoveraWidgets.appex
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target not found!" unless runner_target

# Add Runner.entitlements to Runner build configurations
runner_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# Add Target Dependency so Xcode builds LoveraWidgets before Runner
runner_target.add_dependency(widget_target)

# Create "Embed Foundation Extensions" CopyFiles Build Phase (dstSubfolderSpec = 13 -> PlugIns)
embed_phase = runner_target.copy_files_build_phases.find { |bp| bp.name == 'Embed Foundation Extensions' || bp.dst_subfolder_spec == '13' }
unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed Foundation Extensions'
  embed_phase.dst_path = ''
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  
  # Insert BEFORE 'Thin Binary' phase to avoid Xcode 15/16 circular dependency ("Cycle inside Runner")
  thin_binary_index = runner_target.build_phases.index { |bp| bp.respond_to?(:name) && bp.name == 'Thin Binary' }
  if thin_binary_index
    runner_target.build_phases.insert(thin_binary_index, embed_phase)
  else
    runner_target.build_phases << embed_phase
  end
end

# Add LoveraWidgets.appex product reference to Embed Foundation Extensions phase
appex_ref = widget_target.product_reference
build_file = embed_phase.add_file_reference(appex_ref, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "=== Successfully added #{widget_target_name} WidgetKit Extension target to Runner.xcodeproj! ==="
