require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
output = File.join(root, 'build', 'widget-photo-bridge')
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'URLProbe.xcodeproj'))
sources = project.main_group.new_group('Production bridge + synthetic test fixtures')
base_id = 'com.kevin3627713.sessioncamera.urlprobe'
make = lambda do |name, type, suffix, filenames, header|
  target = project.new_target(type, name, :ios, '18.0')
  filenames.each { |f| target.source_build_phase.add_file_reference(sources.new_file(File.join(root, f))) }
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => base_id + suffix,
      'INFOPLIST_FILE' => File.join(output, name + '.plist'),
      'SWIFT_VERSION' => '5.0', 'CLANG_ENABLE_MODULES' => 'YES',
      'CLANG_ENABLE_OBJC_ARC' => 'YES', 'TARGETED_DEVICE_FAMILY' => '1',
      'IPHONEOS_DEPLOYMENT_TARGET' => '18.0', 'CODE_SIGNING_ALLOWED' => 'NO',
      'CURRENT_PROJECT_VERSION' => '1', 'MARKETING_VERSION' => '1.0',
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG WIDGET_BRIDGE_TEST',
      'GCC_PREPROCESSOR_DEFINITIONS' => ['$(inherited)', 'WIDGET_BRIDGE_TEST=1']
    })
    configuration.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = File.join(root, header) if header
  end
  target
end
host = make.call('URLProbe', :application, '', ['native/WidgetURLProbe/Host.swift', 'native/WidgetPhotoBridgeTests/Registry.m'], nil)
widget = make.call('URLProbeWidget', :app_extension, '.widget', [
  'native/WidgetPhotoBridgeTests/Widget.swift', 'ios/SessionWidgets/WidgetPhotoOpenIntent.swift',
  'ios/SessionWidgets/PhotoBridgeClient.m', 'ios/Shared/SystemPhotosAsset.swift',
  'ios/Shared/PhotoBridgeProtocol.m'
], 'ios/SessionWidgets/PhotoBridgeClient.h')
# Deliberately rewrite the extension identifier independently, as re-signers do.
share = make.call('SessionPhotoBridge', :app_extension, '.rewrittenphotosbridge', [
  'ios/SessionPhotoBridge/PhotosBridgeRequest.swift', 'ios/SessionPhotoBridge/PhotosBridgeHook.m',
  'ios/Shared/SystemPhotosAsset.swift', 'ios/Shared/PhotoBridgeProtocol.m'
], 'ios/SessionPhotoBridge/SessionPhotoBridge-Bridging-Header.h')
tests = make.call('URLProbeUITests', :ui_test_bundle, '.uitests', ['native/WidgetPhotoBridgeTests/UITests.swift'], nil)
[widget, share].each { |t| t.build_configurations.each { |c| c.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' } }
tests.build_configurations.each { |c| c.build_settings['TEST_TARGET_NAME'] = 'URLProbe' }
project.root_object.attributes['TargetAttributes'] = { tests.uuid => { 'TestTargetID' => host.uuid } }
embed = host.new_copy_files_build_phase('Embed production bridge and test widget')
embed.dst_subfolder_spec = '13'
[widget, share].each do |extension|
  host.add_dependency(extension)
  item = embed.add_file_reference(extension.product_reference)
  item.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host); scheme.add_test_target(tests); scheme.set_launch_target(host)
project.save; scheme.save_as(project.path, 'URLProbe', true)
puts project.path
