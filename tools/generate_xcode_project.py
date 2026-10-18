"""Generate the native app project from its owned Swift files and local products."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1] / 'MealTracker'
(root / 'MealTracker.xcodeproj').mkdir(parents=True, exist_ok=True)
objects = []
def obj(i, body):
    objects.append(f'{i:024X} = {{ {body} }};')
def ref(i):
    return f'{i:024X}'
def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)
def refs(values):
    return ', '.join(ref(value) for value in values)

sources, resource_builds, app_children = [], [], []
for index, path in enumerate(sorted((root / 'App').rglob('*.swift'))):
    file_id, build_id = 100 + index * 2, 101 + index * 2
    obj(file_id, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path.relative_to(root))}; sourceTree = "<group>";')
    obj(build_id, f'isa = PBXBuildFile; fileRef = {ref(file_id)};')
    app_children.append(file_id)
    sources.append(build_id)

obj(24, 'isa = PBXFileReference; lastKnownFileType = text.xml; path = App/PrivacyInfo.xcprivacy; sourceTree = "<group>";')
obj(25, f'isa = PBXBuildFile; fileRef = {ref(24)};')
app_children.append(24)
resource_builds.append(25)

# The OS chooses purpose-string language; it is independent of the app preference.
purpose_files = sorted((root / 'App').glob('*.lproj/InfoPlist.strings'))
if purpose_files:
    children = []
    for index, path in enumerate(purpose_files):
        file_id = 400 + index
        obj(file_id, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {quoted(path.parent.stem)}; path = {quoted(path.relative_to(root))}; sourceTree = "<group>";')
        children.append(file_id)
    obj(390, f'isa = PBXVariantGroup; children = ({refs(children)}); name = InfoPlist.strings; sourceTree = "<group>";')
    obj(391, f'isa = PBXBuildFile; fileRef = {ref(390)};')
    app_children.append(390)
    resource_builds.append(391)

products = [name for name in ('MealTrackerCore', 'MealTrackerCatalog', 'MealTrackerDiary', 'MealTrackerOpenFoodFacts', 'MealTrackerLocalization', 'MealTrackerHealth') if (root / 'Sources' / name).is_dir()]
product_refs, framework_builds = [], []
for index, name in enumerate(products):
    product_id, build_id = 500 + index * 2, 501 + index * 2
    obj(product_id, f'isa = XCSwiftPackageProductDependency; package = {ref(20)}; productName = {name};')
    obj(build_id, f'isa = PBXBuildFile; productRef = {ref(product_id)};')
    product_refs.append(product_id)
    framework_builds.append(build_id)

obj(1, f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {ref(10)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, sv, de, Base); mainGroup = {ref(2)}; productRefGroup = {ref(3)}; projectDirPath = ""; projectRoot = ""; targets = ({ref(4)}); packageReferences = ({ref(20)});')
obj(2, f'isa = PBXGroup; children = ({refs(app_children + [3])}); sourceTree = "<group>";')
obj(3, f'isa = PBXGroup; children = ({ref(6)}); name = Products; sourceTree = "<group>";')
obj(4, f'isa = PBXNativeTarget; buildConfigurationList = {ref(11)}; buildPhases = ({ref(7)}, {ref(8)}, {ref(9)}); buildRules = (); dependencies = (); name = MealTracker; packageProductDependencies = ({refs(product_refs)}); productName = MealTracker; productReference = {ref(6)}; productType = "com.apple.product-type.application";')
obj(6, 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MealTracker.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj(7, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({refs(sources)}); runOnlyForDeploymentPostprocessing = 0;')
obj(8, f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({refs(framework_builds)}); runOnlyForDeploymentPostprocessing = 0;')
obj(9, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({refs(resource_builds)}); runOnlyForDeploymentPostprocessing = 0;')
for i, children in [(10, [12, 13]), (11, [14, 15])]:
    obj(i, f'isa = XCConfigurationList; buildConfigurations = ({refs(children)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
for i, name in [(12, 'Debug'), (13, 'Release')]:
    obj(i, f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; SWIFT_VERSION = 5.0; }}; name = {name};')
for i, name in [(14, 'Debug'), (15, 'Release')]:
    settings = 'CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = App/MealTracker.entitlements; CURRENT_PROJECT_VERSION = 2; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = MealTracker; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.healthcare-fitness"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_NSCameraUsageDescription = "Scan a food barcode to find its nutrition information."; INFOPLIST_KEY_NSHealthShareUsageDescription = "Read active and resting energy to compare with your logged meals."; MARKETING_VERSION = 0.2.0; PRODUCT_BUNDLE_IDENTIFIER = com.example.MealTracker; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; TARGETED_DEVICE_FAMILY = 1; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 18.0;'
    settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES;' if name == 'Debug' else ' SWIFT_COMPILATION_MODE = wholemodule; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    obj(i, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {name};')
obj(20, 'isa = XCLocalSwiftPackageReference; relativePath = .;')
(root / 'MealTracker.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {ref(1)}; }}\n')
scheme = root / 'MealTracker.xcodeproj/xcshareddata/xcschemes'
scheme.mkdir(parents=True, exist_ok=True)
(scheme / 'MealTracker.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(4)}" BuildableName="MealTracker.app" BlueprintName="MealTracker" ReferencedContainer="container:MealTracker.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" useMainThreadChecker="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(4)}" BuildableName="MealTracker.app" BlueprintName="MealTracker" ReferencedContainer="container:MealTracker.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
