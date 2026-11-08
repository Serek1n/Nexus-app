# Nexus для iOS: добавляет в сгенерированный проект Xcode (ios/Runner.xcodeproj)
# VPN-расширение NexusTunnel, ядро LibXray.xcframework, права (entitlements),
# гео-базы и код Nexus. Запуск из корня проекта:
#   ruby tool/ios/add_tunnel.rb <версия> <номер сборки>
require 'xcodeproj'

ver = ARGV[0] || '1.0.0'
build = ARGV[1] || '1'
team = ENV['APPLE_TEAM_ID'].to_s.strip

proj = Xcodeproj::Project.open('ios/Runner.xcodeproj')
app = proj.targets.find { |t| t.name == 'Runner' } or abort('нет цели Runner')
abort('NexusTunnel уже добавлен') if proj.targets.any? { |t| t.name == 'NexusTunnel' }

# ── библиотеки ──
fw = proj.frameworks_group
xcf = fw.new_file('LibXray.xcframework', :group)
xcf.path = 'LibXray.xcframework'
xcf.source_tree = 'SOURCE_ROOT'
xcf.last_known_file_type = 'wrapper.xcframework'
ne = fw.new_file('System/Library/Frameworks/NetworkExtension.framework', :sdk_root)
resolv = fw.new_file('usr/lib/libresolv.tbd', :sdk_root)

# ── расширение ──
ext = proj.new_target(:app_extension, 'NexusTunnel', :ios, '15.0', nil, :swift)
unless ext.build_configurations.any? { |c| c.name == 'Profile' }
  rel = ext.build_configurations.find { |c| c.name == 'Release' }
  prof = ext.add_build_configuration('Profile', :release)
  prof.build_settings = rel.build_settings.dup
end
grp = proj.main_group.new_group('NexusTunnel', 'NexusTunnel')
src = grp.new_reference('PacketTunnelProvider.swift')
grp.new_reference('Info.plist')
grp.new_reference('NexusTunnel.entitlements')
ext.add_file_references([src])
[xcf, ne, resolv].each { |f| ext.frameworks_build_phase.add_file_reference(f, true) }

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_NAME'] = 'NexusTunnel'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.nexusvpn.nexus.tunnel'
  s['INFOPLIST_FILE'] = 'NexusTunnel/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'NexusTunnel/NexusTunnel.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = team unless team.empty?
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['ENABLE_BITCODE'] = 'NO'
  s['MARKETING_VERSION'] = ver
  s['CURRENT_PROJECT_VERSION'] = build
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks',
                                  '@executable_path/../../Frameworks']
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
end

# ── приложение ──
runner = proj.main_group['Runner'] or abort('нет группы Runner')
vpn = runner.new_reference('NexusVpn.swift')
app.source_build_phase.add_file_reference(vpn)
runner.new_reference('Runner.entitlements')
%w[geoip.dat geosite.dat nexus-blocked.dat].each do |g|
  next unless File.exist?("ios/Runner/#{g}")
  app.resources_build_phase.add_file_reference(runner.new_reference(g))
end
[xcf, ne, resolv].each { |f| app.frameworks_build_phase.add_file_reference(f, true) }
app.build_configurations.each do |c|
  s = c.build_settings
  s['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = team unless team.empty?
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.nexusvpn.nexus'
end

# Расширение встраивается в Nexus.app/PlugIns. Фаза копирования — перед
# «Thin Binary» Flutter, иначе Xcode видит цикл зависимостей.
app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
thin = app.build_phases.index { |p| p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') }
if thin
  app.build_phases.delete(embed)
  app.build_phases.insert(thin, embed)
end

proj.save
puts "NexusTunnel добавлен (#{ver}+#{build}, команда: #{team.empty? ? 'нет' : team})"
