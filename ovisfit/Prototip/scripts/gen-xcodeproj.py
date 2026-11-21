# Xcode projesini (project.pbxproj + paylaşılan scheme) yeniden üretir. Yeni .swift dosyası ekleyince:
#   python3 scripts/gen-xcodeproj.py "$PWD"   (Prototip klasöründe)
import hashlib, sys, os
root = sys.argv[1]  # Prototip dir
def uid(name): return hashlib.md5(name.encode()).hexdigest().upper()[:24]

core = sorted(f for f in os.listdir(f'{root}/iOS/Core') if f.endswith('.swift'))
ui = sorted(f for f in os.listdir(f'{root}/iOS/UI') if f.endswith('.swift'))
res = [('Assets.xcassets','folder.assetcatalog'),('foods.json','text.json'),('PrivacyInfo.xcprivacy','text.xml')]

objs = []
def add(i, body): objs.append(f'\t\t{i} = {{{body}}};')

src_build, res_build = [], []
def fileref(group, name, ftype, build=None):
    fid = uid('ref/'+group+'/'+name)
    add(fid, f'isa = PBXFileReference; lastKnownFileType = {ftype}; path = {q(name)}; sourceTree = "<group>"; ')
    if build:
        bid = uid('build/'+group+'/'+name)
        add(bid, f'isa = PBXBuildFile; fileRef = {fid}; ')
        (src_build if build=='src' else res_build).append(bid)
    return fid
def q(s): return s if all(c.isalnum() or c in '._/' for c in s) else '"'+s+'"'

core_ids = [fileref('Core', f, 'sourcecode.swift', 'src') for f in core]
ui_ids = [fileref('UI', f, 'sourcecode.swift', 'src') for f in ui]
res_ids = [fileref('Resources', n, t, 'res') for n,t in res]
info_id = fileref('iOS', 'Info.plist', 'text.plist.xml')
ent_id = fileref('iOS', 'OvisFit.entitlements', 'text.plist.entitlements')
base_id = fileref('Config', 'Base.xcconfig', 'text.xcconfig')
localex_id = fileref('Config', 'Local.xcconfig.example', 'text')
w_swift = fileref('Widgets', 'OvisWidgets.swift', 'sourcecode.swift')
w_info = fileref('Widgets', 'Info.plist', 'text.plist.xml')
w_ent = fileref('Widgets', 'OvisWidgets.entitlements', 'text.plist.entitlements')
w_src_build = []
def wbuild(key, fid):
    bid = uid('wbuild/'+key); add(bid, f'isa = PBXBuildFile; fileRef = {fid}; '); w_src_build.append(bid)
wbuild('swift', w_swift)
wbuild('snapshot', uid('ref/Core/WidgetSnapshot.swift'))
ut_swift = fileref('UITests', 'OnboardingUITests.swift', 'sourcecode.swift')
ut_bf = uid('utbuild/swift'); add(ut_bf, f'isa = PBXBuildFile; fileRef = {ut_swift}; ')
xctest_id = uid('product/uitests')
add(xctest_id, 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = OvisFitUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; ')
appex_id = uid('product/appex')
add(appex_id, 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = OvisFitWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; ')
app_id = uid('product')
add(app_id, 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OvisFit.app; sourceTree = BUILT_PRODUCTS_DIR; ')

def group(key, children, path=None, name=None):
    gid = uid('group/'+key)
    extra = (f'path = {path}; ' if path else '') + (f'name = {name}; ' if name else '')
    add(gid, f'isa = PBXGroup; children = ({", ".join(children)}, ); {extra}sourceTree = "<group>"; ')
    return gid
g_core = group('core', core_ids, path='Core')
g_ui = group('ui', ui_ids, path='UI')
g_res = group('res', res_ids, path='Resources')
g_ios = group('ios', [g_core, g_ui, g_res, info_id, ent_id], path='iOS')
g_cfg = group('cfg', [base_id, localex_id], path='Config')
g_prod = group('prod', [app_id, appex_id, xctest_id], name='Products')
g_ut = group('uitests', [ut_swift], path='UITests')
g_w = group('widgets', [w_swift, w_info, w_ent], path='Widgets')
g_main = group('main', [g_ios, g_w, g_ut, g_cfg, g_prod])

p_src = uid('phase/src'); add(p_src, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(src_build)}, ); runOnlyForDeploymentPostprocessing = 0; ')
p_res = uid('phase/res'); add(p_res, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(res_build)}, ); runOnlyForDeploymentPostprocessing = 0; ')
script = r'''# Xcode'dan iPhone'a kurulan Debug derlemesi: Mac'teki geliştirme sunucusunun Bonjour adresini
# uygulama paketindeki DevServer.txt'ye yazar (Info.plist'e dokunmaz). Simülatör ve Release'te dosya boş kalır.
OUT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/DevServer.txt"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
if [ "$CONFIGURATION" = "Debug" ] && [ "$PLATFORM_NAME" = "iphoneos" ]; then
  NAME=$(scutil --get LocalHostName 2>/dev/null || true)
  if [ -n "$NAME" ]; then
    printf 'http://%s.local:8787' "$NAME" > "$OUT"
    echo "Geliştirme sunucusu: http://$NAME.local:8787"
  fi
fi
'''
esc = script.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')
p_sh = uid('phase/sh'); add(p_sh, f'isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; files = ( ); inputFileListPaths = ( ); inputPaths = ( ); name = "Geliştirme sunucusu adresi (Debug, iPhone)"; outputFileListPaths = ( ); outputPaths = ("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/DevServer.txt", ); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = "{esc}"; showEnvVarsInLog = 0; ')
p_fw = uid('phase/fw'); add(p_fw, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; ')

wp_src = uid('wphase/src'); add(wp_src, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(w_src_build)}, ); runOnlyForDeploymentPostprocessing = 0; ')
wp_fw = uid('wphase/fw'); add(wp_fw, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; ')
wp_res = uid('wphase/res'); add(wp_res, 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; ')
embed_bf = uid('build/embed-appex'); add(embed_bf, f'isa = PBXBuildFile; fileRef = {appex_id}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; ')
p_embed = uid('phase/embed'); add(p_embed, f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({embed_bf}, ); name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0; ')

up_src = uid('utphase/src'); add(up_src, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ut_bf}, ); runOnlyForDeploymentPostprocessing = 0; ')
up_fw = uid('utphase/fw'); add(up_fw, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; ')

def settings(d): return 'buildSettings = {' + ' '.join(f'{k} = {v};' for k,v in d.items()) + ' }; '
common = {
 'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES',
 'ENABLE_STRICT_OBJC_MSGSEND':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','IPHONEOS_DEPLOYMENT_TARGET':'17.0',
 'SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','LOCALIZATION_PREFERS_STRING_CATALOGS':'YES',
 'ENABLE_USER_SCRIPT_SANDBOXING':'YES','MTL_FAST_MATH':'YES',
}
proj_debug = dict(common, **{'DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES','GCC_OPTIMIZATION_LEVEL':'0',
  'ONLY_ACTIVE_ARCH':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'"DEBUG $(inherited)"','SWIFT_OPTIMIZATION_LEVEL':'"-Onone"',
  'GCC_PREPROCESSOR_DEFINITIONS':'("DEBUG=1", "$(inherited)", )','MTL_ENABLE_DEBUG_INFO':'INCLUDE_SOURCE'})
proj_release = dict(common, **{'DEBUG_INFORMATION_FORMAT':'"dwarf-with-dsym"','ENABLE_NS_ASSERTIONS':'NO',
  'SWIFT_COMPILATION_MODE':'wholemodule','VALIDATE_PRODUCT':'YES','MTL_ENABLE_DEBUG_INFO':'NO'})
target = {
 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor',
 'CODE_SIGN_STYLE':'Automatic','ENABLE_PREVIEWS':'YES','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_FILE':'iOS/Info.plist',
 'INFOPLIST_KEY_CFBundleDisplayName':'"Ovis Fit"',
 'INFOPLIST_KEY_LSApplicationCategoryType':'"public.app-category.healthcare-fitness"',
 'INFOPLIST_KEY_NSCameraUsageDescription':'"Tabağının fotoğrafını çekip porsiyon tahmini yapmak için kamerayı kullanırız. Fotoğraf yalnızca sen Fotoğrafı analiz et düğmesine dokunduğunda analiz için gönderilir."',
 'INFOPLIST_KEY_NSLocalNetworkUsageDescription':'"Geliştirme sürümünde tabak analizi için aynı ağdaki Ovis Fit sunucusuna bağlanır."',
 'ENABLE_USER_SCRIPT_SANDBOXING':'NO',
 'CODE_SIGN_ENTITLEMENTS':'iOS/OvisFit.entitlements',
 'INFOPLIST_KEY_NSHealthUpdateUsageDescription':'"Ayarlardan açarsan öğün enerjisi ve makroları, su ve kilo kayıtlarını Sağlık uygulamasına yazarız."',
 'INFOPLIST_KEY_NSHealthShareUsageDescription':'"Günlük adım sayını ve hareketle yakılan enerjiyi okuyarak yakılan kaloriyi ve enerji dengeni hesaplarız. Veriler cihazında kalır, paylaşılmaz ve reklam için kullanılmaz."',
 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES',
 'INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait',
 'INFOPLIST_KEY_UIUserInterfaceStyle':'Light',
 'LD_RUNPATH_SEARCH_PATHS':'("$(inherited)", "@executable_path/Frameworks", )',
 'PRODUCT_NAME':'OvisFit','SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"','SUPPORTS_MACCATALYST':'NO',
 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD':'NO',
 'SWIFT_EMIT_LOC_STRINGS':'YES','TARGETED_DEVICE_FAMILY':'1',
}
def cfg(key, name, d, base=None):
    cid = uid('cfg/'+key)
    b = f'baseConfigurationReference = {base}; ' if base else ''
    add(cid, f'isa = XCBuildConfiguration; {b}{settings(d)}name = {name}; ')
    return cid
pd, pr = cfg('pd','Debug',proj_debug), cfg('pr','Release',proj_release)
td, tr = cfg('td','Debug',target,base_id), cfg('tr','Release',target,base_id)
wtarget = {
 'CODE_SIGN_STYLE':'Automatic','CODE_SIGN_ENTITLEMENTS':'Widgets/OvisWidgets.entitlements',
 'GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_FILE':'Widgets/Info.plist',
 'INFOPLIST_KEY_CFBundleDisplayName':'"Ovis Fit"','INFOPLIST_KEY_NSHumanReadableCopyright':'""',
 'LD_RUNPATH_SEARCH_PATHS':'("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks", )',
 'PRODUCT_BUNDLE_IDENTIFIER':'"$(OVIS_BUNDLE_ID).widgets"','PRODUCT_NAME':'OvisFitWidgets',
 'SKIP_INSTALL':'YES','SWIFT_EMIT_LOC_STRINGS':'YES','TARGETED_DEVICE_FAMILY':'1',
 'SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'""',
}
wd, wr = cfg('wd','Debug',wtarget,base_id), cfg('wr','Release',wtarget,base_id)
wl = uid('cl/w'); add(wl, f'isa = XCConfigurationList; buildConfigurations = ({wd}, {wr}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; ')
uttarget = {
 'CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES',
 'PRODUCT_BUNDLE_IDENTIFIER':'"$(OVIS_BUNDLE_ID).uitests"','PRODUCT_NAME':'"$(TARGET_NAME)"',
 'TEST_TARGET_NAME':'OvisFit','TARGETED_DEVICE_FAMILY':'1','SWIFT_EMIT_LOC_STRINGS':'NO',
 'SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"',
}
ud, ur = cfg('utd','Debug',uttarget,base_id), cfg('utr','Release',uttarget,base_id)
utl = uid('cl/ut'); add(utl, f'isa = XCConfigurationList; buildConfigurations = ({ud}, {ur}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; ')
pl = uid('cl/p'); add(pl, f'isa = XCConfigurationList; buildConfigurations = ({pd}, {pr}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; ')
tl = uid('cl/t'); add(tl, f'isa = XCConfigurationList; buildConfigurations = ({td}, {tr}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; ')
tgt = '0E8A3AD980EC179856012B7E'
proj = '98F54143AB4E86B28C3AFEE0'
wtgt = uid('target/widgets')
add(wtgt, f'isa = PBXNativeTarget; buildConfigurationList = {wl}; buildPhases = ({wp_src}, {wp_fw}, {wp_res}, ); buildRules = ( ); dependencies = ( ); name = OvisFitWidgets; productName = OvisFitWidgets; productReference = {appex_id}; productType = "com.apple.product-type.app-extension"; ')
proxy = uid('proxy/widgets'); add(proxy, f'isa = PBXContainerItemProxy; containerPortal = {proj}; proxyType = 1; remoteGlobalIDString = {wtgt}; remoteInfo = OvisFitWidgets; ')
dep = uid('dep/widgets'); add(dep, f'isa = PBXTargetDependency; target = {wtgt}; targetProxy = {proxy}; ')
uttgt = uid('target/uitests')
utproxy = uid('proxy/uitests'); add(utproxy, f'isa = PBXContainerItemProxy; containerPortal = {proj}; proxyType = 1; remoteGlobalIDString = {tgt}; remoteInfo = OvisFit; ')
utdep = uid('dep/uitests'); add(utdep, f'isa = PBXTargetDependency; target = {tgt}; targetProxy = {utproxy}; ')
add(uttgt, f'isa = PBXNativeTarget; buildConfigurationList = {utl}; buildPhases = ({up_src}, {up_fw}, ); buildRules = ( ); dependencies = ({utdep}, ); name = OvisFitUITests; productName = OvisFitUITests; productReference = {xctest_id}; productType = "com.apple.product-type.bundle.ui-testing"; ')
add(tgt, f'isa = PBXNativeTarget; buildConfigurationList = {tl}; buildPhases = ({p_src}, {p_fw}, {p_res}, {p_embed}, {p_sh}, ); buildRules = ( ); dependencies = ({dep}, ); name = OvisFit; productName = OvisFit; productReference = {app_id}; productType = "com.apple.product-type.application"; ')
add(proj, f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{{tgt} = {{CreatedOnToolsVersion = 16.0; }}; {wtgt} = {{CreatedOnToolsVersion = 16.0; }}; {uttgt} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {tgt}; }}; }}; }}; buildConfigurationList = {pl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = tr; hasScannedForEncodings = 0; knownRegions = (tr, Base, ); mainGroup = {g_main}; productRefGroup = {g_prod}; projectDirPath = ""; projectRoot = ""; targets = ({tgt}, {wtgt}, {uttgt}, ); ')

out = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objs) + f'\n\t}};\n\trootObject = {proj};\n}}\n'
open(f'{root}/OvisFit.xcodeproj/project.pbxproj','w').write(out)

scheme_dir = f'{root}/OvisFit.xcodeproj/xcshareddata/xcschemes'
os.makedirs(scheme_dir, exist_ok=True)
ref = f'''<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tgt}" BuildableName = "OvisFit.app" BlueprintName = "OvisFit" ReferencedContainer = "container:OvisFit.xcodeproj"></BuildableReference>'''
open(f'{scheme_dir}/OvisFit.xcscheme','w').write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{uttgt}" BuildableName = "OvisFitUITests.xctest" BlueprintName = "OvisFitUITests" ReferencedContainer = "container:OvisFit.xcodeproj"></BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
      <CommandLineArguments>
         <CommandLineArgument argument = "-OvisScreenshotData" isEnabled = "NO"></CommandLineArgument>
         <CommandLineArgument argument = "-OvisResetData" isEnabled = "NO"></CommandLineArgument>
      </CommandLineArguments>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
''')
print(len(objs), 'objects')
