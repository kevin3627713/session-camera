require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
output = File.join(root, 'build', 'widget-url-probe')
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'URLProbe.xcodeproj'))
sources = project.main_group.new_group('Research only')
base_id = 'com.kevin3627713.sessioncamera.urlprobe'

make = lambda do |name, type, suffix, filenames|
  target = project.new_target(type, name, :ios, '18.0')
  filenames.each { |f| target.source_build_phase.add_file_reference(sources.new_file(File.join(root, 'native', 'WidgetURLProbe', f))) }
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => base_id + suffix,
      'INFOPLIST_FILE' => File.join(output, name + '.plist'),
      'SWIFT_VERSION' => '5.0', 'CLANG_ENABLE_MODULES' => 'YES',
      'CLANG_ENABLE_OBJC_ARC' => 'YES', 'TARGETED_DEVICE_FAMILY' => '1',
      'IPHONEOS_DEPLOYMENT_TARGET' => '18.0', 'CODE_SIGNING_ALLOWED' => 'NO',
      'CURRENT_PROJECT_VERSION' => '1', 'MARKETING_VERSION' => '1.0'
    })
  end
  target
end
host = make.call('URLProbe', :application, '', ['Host.swift', 'BackgroundIntent.swift', 'Dispatch.m'])
widget = make.call('URLProbeWidget', :app_extension, '.widget', ['Widget.swift', 'BackgroundIntent.swift', 'Dispatch.m'])
share = make.call('URLProbeShare', :app_extension, '.share', ['Share.m', 'Dispatch.m'])
tests = make.call('URLProbeUITests', :ui_test_bundle, '.uitests', ['UITests.swift'])
[widget, host].each { |t| t.build_configurations.each do |c|
  c.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = File.join(root, 'native', 'WidgetURLProbe', 'Dispatch.h')
end }
widget.build_configurations.each { |c| c.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' }
share.build_configurations.each { |c| c.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' }
tests.build_configurations.each { |c| c.build_settings['TEST_TARGET_NAME'] = 'URLProbe' }
project.root_object.attributes['TargetAttributes'] = { tests.uuid => { 'TestTargetID' => host.uuid } }
embed = host.new_copy_files_build_phase('Embed research extensions')
embed.dst_subfolder_spec = '13'
[widget, share].each do |extension|
  host.add_dependency(extension)
  item = embed.add_file_reference(extension.product_reference)
  item.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.add_test_target(tests)
scheme.set_launch_target(host)
project.save
scheme.save_as(project.path, 'URLProbe', true)
puts project.path
