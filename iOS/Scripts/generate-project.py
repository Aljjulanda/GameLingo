#!/usr/bin/env python3
"""Deterministic Xcode 14-readable project; no XcodeGen or CocoaPods installation required."""
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)


def main():
    objects = []

    def obj(name, body):
        objects.append(f'\t\t{uid(name)} = {{ {body} }};')
        return uid(name)

    def ref(path, kind=None):
        extension = pathlib.Path(path).suffix
        kind = kind or {'.swift': 'sourcecode.swift', '.m': 'sourcecode.c.objc', '.mm': 'sourcecode.cpp.objcpp', '.h': 'sourcecode.c.h', '.json': 'text.json', '.plist': 'text.plist.xml', '.xcprivacy': 'text.xml', '.txt': 'text'}.get(extension, 'text')
        return obj('file:' + path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;')

    def build(path, phase, kind=None):
        reference = ref(path, kind)
        return obj('build:' + phase + ':' + path, f'isa = PBXBuildFile; fileRef = {reference};')

    source_paths = sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'GameLingo').rglob('*.swift'))
    source_paths += ['Native/GLTranslation.mm', 'Native/GLIdentity.m']
    sources = [build(p, 'app') for p in source_paths]
    resource_paths = ['GameLingo/Core/Resources/tv-display-schema.json', 'GameLingo/Resources/PrivacyInfo.xcprivacy', 'GameLingo/Resources/ThirdPartyNotices.txt']
    resources = [build(p, 'resource') for p in resource_paths]
    test_paths = sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'GameLingoTests').glob('*.swift'))
    tests = [build(p, 'test') for p in test_paths]
    ui_paths = sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'GameLingoPickerUITests').glob('*.swift'))
    ui_tests = [build(p, 'ui') for p in ui_paths]
    test_resources = [build('GameLingoTests/Fixtures/en_ar', 'testresource', 'folder')]
    headers = [ref(p) for p in ['Native/GLRemotePlay.h', 'Native/GLTranslation.h', 'Native/GameLingo-Bridging-Header.h', 'GameLingo/Resources/Info.plist', 'GameLingo/Resources/GameLingo.entitlements']]
    file_ids = [uid('file:' + p) for p in source_paths + resource_paths + test_paths + ui_paths + ['GameLingoTests/Fixtures/en_ar']] + headers

    obj('product:app', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = GameLingo.app; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('product:test', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = GameLingoTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('product:ui', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = GameLingoPickerUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('group:products', f'isa = PBXGroup; children = ({uid("product:app")}, {uid("product:test")}, {uid("product:ui")},); name = Products; sourceTree = "<group>";')
    obj('group:root', f'isa = PBXGroup; children = ({", ".join(file_ids)}, {uid("group:products")},); sourceTree = "<group>";')

    for name, isa, files in [('app:sources', 'PBXSourcesBuildPhase', sources), ('app:resources', 'PBXResourcesBuildPhase', resources), ('test:sources', 'PBXSourcesBuildPhase', tests), ('test:resources', 'PBXResourcesBuildPhase', test_resources), ('ui:sources', 'PBXSourcesBuildPhase', ui_tests), ('ui:resources', 'PBXResourcesBuildPhase', [])]:
        file_list = ', '.join(files) + (',' if files else '')
        obj(name, f'isa = {isa}; buildActionMask = 2147483647; files = ({file_list}); runOnlyForDeploymentPostprocessing = 0;')

    obj('package:zip', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/weichsel/ZIPFoundation.git"; requirement = { kind = exactVersion; version = 0.9.19; };')
    obj('package:product', f'isa = XCSwiftPackageProductDependency; package = {uid("package:zip")}; productName = ZIPFoundation;')
    obj('package:build', f'isa = PBXBuildFile; productRef = {uid("package:product")};')
    obj('app:frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({uid("package:build")},); runOnlyForDeploymentPostprocessing = 0;')
    obj('package:testproduct', f'isa = XCSwiftPackageProductDependency; package = {uid("package:zip")}; productName = ZIPFoundation;')
    obj('package:testbuild', f'isa = PBXBuildFile; productRef = {uid("package:testproduct")};')
    obj('test:frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({uid("package:testbuild")},); runOnlyForDeploymentPostprocessing = 0;')
    obj('ui:frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj('dependency:proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:app")}; remoteInfo = GameLingo;')
    obj('dependency:app', f'isa = PBXTargetDependency; target = {uid("target:app")}; targetProxy = {uid("dependency:proxy")};')

    base = {'IPHONEOS_DEPLOYMENT_TARGET': '16.0', 'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'CLANG_CXX_LANGUAGE_STANDARD': 'c++17', 'SDKROOT': 'iphoneos', 'TARGETED_DEVICE_FAMILY': '1', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO', 'ENABLE_USER_SCRIPT_SANDBOXING': 'NO'}
    app = {'PRODUCT_NAME': 'GameLingo', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.gamelingo.ios', 'INFOPLIST_FILE': 'GameLingo/Resources/Info.plist', 'SWIFT_OBJC_BRIDGING_HEADER': 'Native/GameLingo-Bridging-Header.h', 'HEADER_SEARCH_PATHS': '$(inherited) $(SRCROOT)/Native $(SRCROOT)/.build/include', 'LIBRARY_SEARCH_PATHS': '$(inherited) $(SRCROOT)/.build/lib/$(PLATFORM_NAME)', 'OTHER_LDFLAGS': '$(inherited) -lGameLingoNative -lc++ -lz -liconv -lsqlite3 -framework Accelerate -framework Security -framework SystemConfiguration -framework CFNetwork', 'CODE_SIGN_ENTITLEMENTS': 'GameLingo/Resources/GameLingo.entitlements', 'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'NO', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks', 'SWIFT_EMIT_LOC_STRINGS': 'YES', 'ENABLE_BITCODE': 'NO'}
    test = {'PRODUCT_NAME': 'GameLingoTests', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.gamelingo.ios.tests', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/GameLingo.app/GameLingo', 'BUNDLE_LOADER': '$(TEST_HOST)', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'}
    ui = {'PRODUCT_NAME': 'GameLingoPickerUITests', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.gamelingo.ios.pickerUITests', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'GameLingo', 'CODE_SIGN_STYLE': 'Automatic', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'}
    for scope, specific in [('project', base), ('app', app), ('test', test), ('ui', ui)]:
        for configuration in ('Debug', 'Release'):
            settings = specific.copy()
            if scope == 'project':
                settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if configuration == 'Debug' else '-O', 'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym', 'ENABLE_TESTABILITY': 'YES' if configuration == 'Debug' else 'NO', 'GCC_PREPROCESSOR_DEFINITIONS': '$(inherited) DEBUG=1' if configuration == 'Debug' else '$(inherited)', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if configuration == 'Debug' else ''})
            body = ' '.join(f'{key} = {quoted(value)};' for key, value in settings.items())
            obj(f'config:{scope}:{configuration}', f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {configuration};')
        obj(f'configlist:{scope}', f'isa = XCConfigurationList; buildConfigurations = ({uid(f"config:{scope}:Debug")}, {uid(f"config:{scope}:Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    obj('target:app', f'isa = PBXNativeTarget; buildConfigurationList = {uid("configlist:app")}; buildPhases = ({uid("app:sources")}, {uid("app:frameworks")}, {uid("app:resources")},); buildRules = (); dependencies = (); name = GameLingo; packageProductDependencies = ({uid("package:product")},); productName = GameLingo; productReference = {uid("product:app")}; productType = "com.apple.product-type.application";')
    obj('target:test', f'isa = PBXNativeTarget; buildConfigurationList = {uid("configlist:test")}; buildPhases = ({uid("test:sources")}, {uid("test:frameworks")}, {uid("test:resources")},); buildRules = (); dependencies = ({uid("dependency:app")},); name = GameLingoTests; packageProductDependencies = ({uid("package:testproduct")},); productName = GameLingoTests; productReference = {uid("product:test")}; productType = "com.apple.product-type.bundle.unit-test";')
    obj('target:ui', f'isa = PBXNativeTarget; buildConfigurationList = {uid("configlist:ui")}; buildPhases = ({uid("ui:sources")}, {uid("ui:frameworks")}, {uid("ui:resources")},); buildRules = (); dependencies = ({uid("dependency:app")},); name = GameLingoPickerUITests; productName = GameLingoPickerUITests; productReference = {uid("product:ui")}; productType = "com.apple.product-type.bundle.ui-testing";')
    obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1420; TargetAttributes = {{ {uid("target:app")} = {{ CreatedOnToolsVersion = 14.2; }}; {uid("target:test")} = {{ CreatedOnToolsVersion = 14.2; TestTargetID = {uid("target:app")}; }}; {uid("target:ui")} = {{ CreatedOnToolsVersion = 14.2; TestTargetID = {uid("target:app")}; }}; }}; }}; buildConfigurationList = {uid("configlist:project")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ar; hasScannedForEncodings = 0; knownRegions = (ar,en,Base); mainGroup = {uid("group:root")}; packageReferences = ({uid("package:zip")},); productRefGroup = {uid("group:products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target:app")}, {uid("target:test")}, {uid("target:ui")},);')
    project = ROOT / 'GameLingo.xcodeproj'
    project.mkdir(exist_ok=True)
    content = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {uid("project")};\n}}\n'
    (project / 'project.pbxproj').write_text(content, encoding='utf-8', newline='\n')
    scheme = project / 'xcshareddata' / 'xcschemes' / 'GameLingo.xcscheme'
    scheme.parent.mkdir(parents=True, exist_ok=True)
    app_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:app")}" BuildableName="GameLingo.app" BlueprintName="GameLingo" ReferencedContainer="container:GameLingo.xcodeproj"/>'
    test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:test")}" BuildableName="GameLingoTests.xctest" BlueprintName="GameLingoTests" ReferencedContainer="container:GameLingo.xcodeproj"/>'
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1420" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding='utf-8', newline='\n')
    ui_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:ui")}" BuildableName="GameLingoPickerUITests.xctest" BlueprintName="GameLingoPickerUITests" ReferencedContainer="container:GameLingo.xcodeproj"/>'
    ui_scheme = scheme.with_name('GameLingoPickerUI.xcscheme')
    ui_scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1420" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{ui_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''',encoding='utf-8',newline='\n')


if __name__ == '__main__':
    main()
