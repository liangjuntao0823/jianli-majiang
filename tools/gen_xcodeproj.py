#!/usr/bin/env python3
"""从文件树生成 JianliMahjong.xcodeproj。

放在仓库里是刻意的：没有 Mac 也能改工程结构，跑一次 python3 tools/gen_xcodeproj.py
就能把新加的 .swift 文件挂进 target，不用手改 pbxproj。
"""

import hashlib
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "App"
PROJ = ROOT / "JianliMahjong.xcodeproj"
PRODUCT = "JianliMahjong"
BUNDLE_ID = "com.liangtao.jianlimajiang"
DEPLOYMENT = "17.0"


def oid(key: str) -> str:
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def sources():
    return sorted(str(p.relative_to(APP)) for p in APP.rglob("*.swift"))


def build():
    files = sources()
    refs = {f: oid("ref:" + f) for f in files}
    builds = {f: oid("build:" + f) for f in files}

    file_ref_lines = "\n".join(
        f'\t\t{refs[f]} /* {os.path.basename(f)} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = "{f}"; sourceTree = "<group>"; }};'
        for f in files
    )
    build_file_lines = "\n".join(
        f'\t\t{builds[f]} /* {os.path.basename(f)} in Sources */ = {{isa = PBXBuildFile; '
        f'fileRef = {refs[f]} /* {os.path.basename(f)} */; }};'
        for f in files
    )

    product_ref = oid("product")
    plist_ref = oid("ref:Info.plist")
    app_group = oid("group:App")
    products_group = oid("group:Products")
    main_group = oid("group:main")
    project = oid("project")
    target = oid("target")
    sources_phase = oid("phase:sources")
    frameworks_phase = oid("phase:frameworks")
    resources_phase = oid("phase:resources")
    project_cfg_list = oid("cfglist:project")
    target_cfg_list = oid("cfglist:target")
    cfg_project_debug = oid("cfg:project:debug")
    cfg_project_release = oid("cfg:project:release")
    cfg_target_debug = oid("cfg:target:debug")
    cfg_target_release = oid("cfg:target:release")
    pkg_ref = oid("pkg")
    pkg_product = oid("pkgproduct")
    pkg_build = oid("pkgbuild")

    app_children = "\n".join(
        f'\t\t\t\t{refs[f]} /* {os.path.basename(f)} */,' for f in files
    )

    common = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = %s;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = minimal;
\t\t\t\tSWIFT_VERSION = 5.0;
""" % DEPLOYMENT

    target_common = """\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = App/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = %s;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
""" % BUNDLE_ID

    content = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_file_lines}
\t\t{pkg_build} /* JianliCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {pkg_product} /* JianliCore */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_ref_lines}
\t\t{plist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\t{product_ref} /* {PRODUCT}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PRODUCT}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{pkg_build} /* JianliCore in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_group} /* App */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product_ref} /* {PRODUCT}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{app_group} /* App */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{app_children}
\t\t\t\t{plist_ref} /* Info.plist */,
\t\t\t);
\t\t\tpath = App;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target} /* {PRODUCT} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_cfg_list} /* Build configuration list for PBXNativeTarget "{PRODUCT}" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {PRODUCT};
\t\t\tpackageProductDependencies = (
\t\t\t\t{pkg_product} /* JianliCore */,
\t\t\t);
\t\t\tproductName = {PRODUCT};
\t\t\tproductReference = {product_ref} /* {PRODUCT}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_cfg_list} /* Build configuration list for PBXProject "{PRODUCT}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = zh_CN;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tzh_CN,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tpackageReferences = (
\t\t\t\t{pkg_ref} /* XCLocalSwiftPackageReference "Packages/JianliCore" */,
\t\t\t);
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target} /* {PRODUCT} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(f"\t\t\t\t{builds[f]} /* {os.path.basename(f)} in Sources */," for f in files)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{cfg_project_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{common}\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{cfg_project_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{common}\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{cfg_target_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_common}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{cfg_target_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_common}\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_cfg_list} /* Build configuration list for PBXProject "{PRODUCT}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{cfg_project_debug} /* Debug */,
\t\t\t\t{cfg_project_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_cfg_list} /* Build configuration list for PBXNativeTarget "{PRODUCT}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{cfg_target_debug} /* Debug */,
\t\t\t\t{cfg_target_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{pkg_ref} /* XCLocalSwiftPackageReference "Packages/JianliCore" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = Packages/JianliCore;
\t\t}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{pkg_product} /* JianliCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {pkg_ref} /* XCLocalSwiftPackageReference "Packages/JianliCore" */;
\t\t\tproductName = JianliCore;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {project} /* Project object */;
}}
"""

    PROJ.mkdir(parents=True, exist_ok=True)
    (PROJ / "project.pbxproj").write_text(content)

    scheme_dir = PROJ / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / f"{PRODUCT}.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference
               BuildableIdentifier="primary"
               BlueprintIdentifier="{target}"
               BuildableName="{PRODUCT}.app"
               BlueprintName="{PRODUCT}"
               ReferencedContainer="container:{PRODUCT}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresStopOnLaunch="NO" askOnLaunch="NO" selectedDebugger="YES" selectedLauncher="YES" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="{target}"
            BuildableName="{PRODUCT}.app"
            BlueprintName="{PRODUCT}"
            ReferencedContainer="container:{PRODUCT}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="{target}"
            BuildableName="{PRODUCT}.app"
            BlueprintName="{PRODUCT}"
            ReferencedContainer="container:{PRODUCT}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
""")

    print(f"wrote {PROJ}/project.pbxproj with {len(files)} swift files")


if __name__ == "__main__":
    build()
