require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
output = File.join(root, 'build', 'photos-navigation-probe')
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'PhotosNavigationProbe.xcodeproj'))
group = project.main_group.new_group('Standalone Photos navigation diagnostic')
base_id = 'com.kevin3627713.photosnavigationprobe'
source = File.join(root, 'native', 'PhotosNavigationProbe')

make = lambda do |name, kind, suffix, files|
  target = project.new_target(kind, name, :ios, '18.0')
  files.each { |file| target.source_build_phase.add_file_reference(group.new_file(File.join(source, file))) }
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => base_id + suffix,
      'INFOPLIST_FILE' => File.join(output, name + '.plist'),
      'SWIFT_VERSION' => '5.0', 'SWIFT_STRICT_CONCURRENCY' => 'minimal',
      'CLANG_ENABLE_MODULES' => 'YES', 'CLANG_ENABLE_OBJC_ARC' => 'YES',
      'TARGETED_DEVICE_FAMILY' => '1', 'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
      'CODE_SIGNING_ALLOWED' => 'NO', 'CURRENT_PROJECT_VERSION' => '4', 'MARKETING_VERSION' => '0.1.3',
      'SWIFT_OBJC_BRIDGING_HEADER' => File.join(source, 'ProbeBridge.h')
    })
  end
  target
end

host = make.call('PhotosNavigationProbe', :application, '', ['App.swift', 'PhotoLibrary.swift', 'URLCandidates.swift', 'ProbeBridge.m', 'AppLaunch.m'])
share = make.call('PhotosNavigationShare', :app_extension, '.share', ['Share.m', 'ProbeBridge.m', 'AppLaunch.m'])
share.build_configurations.each { |config| config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' }
host.resources_build_phase.add_file_reference(group.new_file(File.join(source, 'Assets.xcassets')))
host.build_configurations.each { |config| config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon' }
host.add_dependency(share)
embed = host.new_copy_files_build_phase('Embed diagnostic Share extension')
embed.dst_subfolder_spec = '13'
item = embed.add_file_reference(share.product_reference)
item.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

common = {
  'CFBundleDevelopmentRegion' => 'zh_CN', 'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
  'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion' => '6.0',
  'CFBundleName' => '$(PRODUCT_NAME)', 'CFBundleShortVersionString' => '$(MARKETING_VERSION)',
  'CFBundleVersion' => '$(CURRENT_PROJECT_VERSION)',
  'NSPhotoLibraryUsageDescription' => '选择相册和照片，读取真实标识，用于测试系统照片的跳转行为。'
}
Xcodeproj::Plist.write_to_path(common.merge({
  'CFBundleDisplayName' => '照片跳转诊断', 'CFBundlePackageType' => 'APPL',
  'LSRequiresIPhoneOS' => true, 'UIRequiredDeviceCapabilities' => ['arm64'],
  'UILaunchScreen' => {}, 'UISupportedInterfaceOrientations' => ['UIInterfaceOrientationPortrait'],
  'UIApplicationSceneManifest' => { 'UIApplicationSupportsMultipleScenes' => false },
  'LSApplicationQueriesSchemes' => ['photos', 'photos-navigation', 'photos-redirect']
}), File.join(output, 'PhotosNavigationProbe.plist'))
Xcodeproj::Plist.write_to_path(common.merge({
  'CFBundleDisplayName' => '照片跳转诊断中转', 'CFBundlePackageType' => 'XPC!',
  'NSExtension' => {
    'NSExtensionPointIdentifier' => 'com.apple.share-services',
    'NSExtensionPrincipalClass' => 'PhotosNavigationShareController',
    'NSExtensionAttributes' => { 'NSExtensionActivationRule' => 'FALSEPREDICATE' }
  }
}), File.join(output, 'PhotosNavigationShare.plist'))

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.set_launch_target(host)
project.save
scheme.save_as(project.path, 'PhotosNavigationProbe', true)
puts project.path
