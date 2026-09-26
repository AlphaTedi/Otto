#!/usr/bin/env python3
"""Generate a minimal .xcodeproj/project.pbxproj for NotchSnap macOS app."""

import os
import hashlib
import uuid

# The folder this script lives in, so the checkout can be moved or renamed.
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ_DIR = os.path.join(PROJECT_ROOT, "NotchSnap.xcodeproj")
PRODUCT_NAME = "NotchSnap"
BUNDLE_ID = "com.notchsnap.app"
DEPLOYMENT_TARGET = "13.0"
ORG_NAME = "NotchSnap"

# All swift source files relative to PROJECT_ROOT
SOURCE_FILES = [
    "NotchSnap/App/NotchSnapApp.swift",
    "NotchSnap/App/AppState.swift",
    "NotchSnap/App/Permissions.swift",
    "NotchSnap/App/SettingsView.swift",
    "NotchSnap/App/OnboardingView.swift",
    "NotchSnap/Models/AppSettings.swift",
    "NotchSnap/Models/AnnotationModel.swift",
    "NotchSnap/Models/ScreenshotItem.swift",
    "NotchSnap/Capture/CaptureManager.swift",
    "NotchSnap/Capture/HotkeyManager.swift",
    "NotchSnap/Capture/AreaSelector.swift",
    "NotchSnap/Notch/NotchController.swift",
    "NotchSnap/Notch/NotchShapeView.swift",
    "NotchSnap/Notch/NotchRootView.swift",
    "NotchSnap/Notch/NotchPanelView.swift",
    "NotchSnap/Notch/NotchExpandedView.swift",
    "NotchSnap/Notch/ScreenshotThumbnail.swift",
    "NotchSnap/Notch/DraggableImageView.swift",
    "NotchSnap/Notch/DraggableThumbnail.swift",
    "NotchSnap/Editor/EditorWindowController.swift",
    "NotchSnap/Editor/EditorView.swift",
    "NotchSnap/Editor/Canvas/AnnotationCanvas.swift",
    "NotchSnap/Editor/Canvas/DrawingEngine.swift",
    "NotchSnap/Editor/Canvas/AnnotationLayer.swift",
    "NotchSnap/Editor/Tools/ToolbarView.swift",
    "NotchSnap/Editor/Tools/ColorPicker.swift",
    "NotchSnap/Editor/Tools/BrushSettings.swift",
    "NotchSnap/Editor/Export/ExportManager.swift",
    "NotchSnap/Editor/Export/DragImageProvider.swift",
    "NotchSnap/Editor/Export/TempFileManager.swift",
]

RESOURCE_FILES = [
    "NotchSnap/Resources/Assets.xcassets",
]

INFO_PLIST = "NotchSnap/Resources/Info.plist"
ENTITLEMENTS = "NotchSnap/Resources/NotchSnap.entitlements"

FRAMEWORKS = [
    "AppKit.framework",
    "SwiftUI.framework",
    "ScreenCaptureKit.framework",
    "CoreGraphics.framework",
    "UniformTypeIdentifiers.framework",
    "ServiceManagement.framework",
]

# Groups matching directory structure
GROUPS = {
    "NotchSnap": [
        "NotchSnap/App",
        "NotchSnap/Models",
        "NotchSnap/Capture",
        "NotchSnap/Notch",
        "NotchSnap/Editor",
        "NotchSnap/Resources",
    ],
    "NotchSnap/App": [],
    "NotchSnap/Models": [],
    "NotchSnap/Capture": [],
    "NotchSnap/Notch": [],
    "NotchSnap/Editor": [
        "NotchSnap/Editor/Canvas",
        "NotchSnap/Editor/Tools",
        "NotchSnap/Editor/Export",
    ],
    "NotchSnap/Editor/Canvas": [],
    "NotchSnap/Editor/Tools": [],
    "NotchSnap/Editor/Export": [],
    "NotchSnap/Resources": [],
}

# ---- UUID generation ----
_counter = 0
def make_id(name):
    global _counter
    _counter += 1
    h = hashlib.md5(f"{name}-{_counter}".encode()).hexdigest().upper()
    return h[:24]

# ---- Assign IDs ----
ids = {}

# Project
ids["project"] = make_id("project")
ids["main_group"] = make_id("main_group")
ids["products_group"] = make_id("products_group")
ids["frameworks_group"] = make_id("frameworks_group")

# Target
ids["native_target"] = make_id("native_target")
ids["product_ref"] = make_id("product_ref")

# Build config list
ids["project_config_list"] = make_id("project_config_list")
ids["project_debug_config"] = make_id("project_debug_config")
ids["project_release_config"] = make_id("project_release_config")
ids["target_config_list"] = make_id("target_config_list")
ids["target_debug_config"] = make_id("target_debug_config")
ids["target_release_config"] = make_id("target_release_config")

# Build phases
ids["sources_phase"] = make_id("sources_phase")
ids["frameworks_phase"] = make_id("frameworks_phase")
ids["resources_phase"] = make_id("resources_phase")

# Source file refs and build files
source_file_refs = {}
source_build_files = {}
for f in SOURCE_FILES:
    name = os.path.basename(f)
    source_file_refs[f] = make_id(f"fileref_{f}")
    source_build_files[f] = make_id(f"buildfile_{f}")

# Resource file refs and build files
resource_file_refs = {}
resource_build_files = {}
for f in RESOURCE_FILES:
    name = os.path.basename(f)
    resource_file_refs[f] = make_id(f"fileref_{f}")
    resource_build_files[f] = make_id(f"buildfile_{f}")

# Info.plist and entitlements refs
ids["info_plist_ref"] = make_id("info_plist_ref")
ids["entitlements_ref"] = make_id("entitlements_ref")

# Framework file refs and build files
fw_file_refs = {}
fw_build_files = {}
for fw in FRAMEWORKS:
    fw_file_refs[fw] = make_id(f"fwref_{fw}")
    fw_build_files[fw] = make_id(f"fwbuild_{fw}")

# Group IDs
group_ids = {}
for g in GROUPS:
    group_ids[g] = make_id(f"group_{g}")


def files_in_group(group_path):
    """Return source/resource files belonging to this group directory."""
    result = []
    for f in SOURCE_FILES:
        if os.path.dirname(f) == group_path:
            result.append((os.path.basename(f), source_file_refs[f]))
    for f in RESOURCE_FILES:
        if os.path.dirname(f) == group_path:
            result.append((os.path.basename(f), resource_file_refs[f]))
    # Info.plist and entitlements
    if group_path == "NotchSnap/Resources":
        result.append(("Info.plist", ids["info_plist_ref"]))
        result.append(("NotchSnap.entitlements", ids["entitlements_ref"]))
    return result


def build_group_section(group_path):
    """Build PBXGroup entry."""
    name = os.path.basename(group_path)
    gid = group_ids[group_path]
    children = []
    # Sub-groups
    for sub in GROUPS[group_path]:
        children.append(group_ids[sub])
    # Files
    for fname, fid in files_in_group(group_path):
        children.append(fid)

    children_str = "\n".join(f"\t\t\t\t{c} /* {c} */," for c in children)
    # Use path for the group
    path = name
    if group_path == "NotchSnap":
        path = "NotchSnap"

    return f"""\t\t{gid} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children_str}
\t\t\t);
\t\t\tpath = "{path}";
\t\t\tsourceTree = "<group>";
\t\t}};"""


def generate_pbxproj():
    lines = []
    w = lines.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w("")

    # ---- PBXBuildFile ----
    w("/* Begin PBXBuildFile section */")
    for f in SOURCE_FILES:
        name = os.path.basename(f)
        w(f"\t\t{source_build_files[f]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {source_file_refs[f]} /* {name} */; }};")
    for f in RESOURCE_FILES:
        name = os.path.basename(f)
        w(f"\t\t{resource_build_files[f]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {resource_file_refs[f]} /* {name} */; }};")
    for fw in FRAMEWORKS:
        w(f"\t\t{fw_build_files[fw]} /* {fw} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fw_file_refs[fw]} /* {fw} */; }};")
    w("/* End PBXBuildFile section */")
    w("")

    # ---- PBXFileReference ----
    w("/* Begin PBXFileReference section */")
    for f in SOURCE_FILES:
        name = os.path.basename(f)
        w(f'\t\t{source_file_refs[f]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};')
    for f in RESOURCE_FILES:
        name = os.path.basename(f)
        w(f'\t\t{resource_file_refs[f]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "{name}"; sourceTree = "<group>"; }};')
    w(f'\t\t{ids["info_plist_ref"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Info.plist"; sourceTree = "<group>"; }};')
    w(f'\t\t{ids["entitlements_ref"]} /* NotchSnap.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "NotchSnap.entitlements"; sourceTree = "<group>"; }};')
    for fw in FRAMEWORKS:
        w(f'\t\t{fw_file_refs[fw]} /* {fw} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = "{fw}"; path = "System/Library/Frameworks/{fw}"; sourceTree = SDKROOT; }};')
    w(f'\t\t{ids["product_ref"]} /* {PRODUCT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{PRODUCT_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
    w("/* End PBXFileReference section */")
    w("")

    # ---- PBXFrameworksBuildPhase ----
    w("/* Begin PBXFrameworksBuildPhase section */")
    fw_entries = "\n".join(f"\t\t\t\t{fw_build_files[fw]} /* {fw} in Frameworks */," for fw in FRAMEWORKS)
    w(f"""\t\t{ids["frameworks_phase"]} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{fw_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};""")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")

    # ---- PBXGroup ----
    w("/* Begin PBXGroup section */")

    # Main group
    main_children = [group_ids["NotchSnap"], ids["frameworks_group"], ids["products_group"]]
    main_children_str = "\n".join(f"\t\t\t\t{c}," for c in main_children)
    w(f"""\t\t{ids["main_group"]} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{main_children_str}
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};""")

    # Products group
    w(f"""\t\t{ids["products_group"]} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids["product_ref"]} /* {PRODUCT_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};""")

    # Frameworks group
    fw_children = "\n".join(f"\t\t\t\t{fw_file_refs[fw]} /* {fw} */," for fw in FRAMEWORKS)
    w(f"""\t\t{ids["frameworks_group"]} /* Frameworks */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{fw_children}
\t\t\t);
\t\t\tname = Frameworks;
\t\t\tsourceTree = "<group>";
\t\t}};""")

    # Source groups
    for g in GROUPS:
        w(build_group_section(g))

    w("/* End PBXGroup section */")
    w("")

    # ---- PBXNativeTarget ----
    w("/* Begin PBXNativeTarget section */")
    w(f"""\t\t{ids["native_target"]} /* {PRODUCT_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ids["target_config_list"]} /* Build configuration list for PBXNativeTarget "{PRODUCT_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{ids["sources_phase"]} /* Sources */,
\t\t\t\t{ids["frameworks_phase"]} /* Frameworks */,
\t\t\t\t{ids["resources_phase"]} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {PRODUCT_NAME};
\t\t\tproductName = {PRODUCT_NAME};
\t\t\tproductReference = {ids["product_ref"]} /* {PRODUCT_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};""")
    w("/* End PBXNativeTarget section */")
    w("")

    # ---- PBXProject ----
    w("/* Begin PBXProject section */")
    w(f"""\t\t{ids["project"]} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tORGANIZATIONNAME = "{ORG_NAME}";
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{ids["native_target"]} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {ids["project_config_list"]} /* Build configuration list for PBXProject "{PRODUCT_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {ids["main_group"]};
\t\t\tproductRefGroup = {ids["products_group"]} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ids["native_target"]} /* {PRODUCT_NAME} */,
\t\t\t);
\t\t}};""")
    w("/* End PBXProject section */")
    w("")

    # ---- PBXResourcesBuildPhase ----
    w("/* Begin PBXResourcesBuildPhase section */")
    res_entries = "\n".join(f"\t\t\t\t{resource_build_files[f]} /* {os.path.basename(f)} in Resources */," for f in RESOURCE_FILES)
    w(f"""\t\t{ids["resources_phase"]} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{res_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};""")
    w("/* End PBXResourcesBuildPhase section */")
    w("")

    # ---- PBXSourcesBuildPhase ----
    w("/* Begin PBXSourcesBuildPhase section */")
    src_entries = "\n".join(f"\t\t\t\t{source_build_files[f]} /* {os.path.basename(f)} in Sources */," for f in SOURCE_FILES)
    w(f"""\t\t{ids["sources_phase"]} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{src_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};""")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    # ---- XCBuildConfiguration ----
    w("/* Begin XCBuildConfiguration section */")

    # Project-level Debug
    w(f"""\t\t{ids["project_debug_config"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) DEBUG";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};""")

    # Project-level Release
    w(f"""\t\t{ids["project_release_config"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t}};
\t\t\tname = Release;
\t\t}};""")

    # Target-level Debug
    w(f"""\t\t{ids["target_debug_config"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = NotchSnap/Resources/NotchSnap.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = NotchSnap/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_LSUIElement = YES;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};""")

    # Target-level Release
    w(f"""\t\t{ids["target_release_config"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = NotchSnap/Resources/NotchSnap.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = NotchSnap/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_LSUIElement = YES;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};""")

    w("/* End XCBuildConfiguration section */")
    w("")

    # ---- XCConfigurationList ----
    w("/* Begin XCConfigurationList section */")
    w(f"""\t\t{ids["project_config_list"]} /* Build configuration list for PBXProject "{PRODUCT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids["project_debug_config"]} /* Debug */,
\t\t\t\t{ids["project_release_config"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};""")
    w(f"""\t\t{ids["target_config_list"]} /* Build configuration list for PBXNativeTarget "{PRODUCT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids["target_debug_config"]} /* Debug */,
\t\t\t\t{ids["target_release_config"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};""")
    w("/* End XCConfigurationList section */")
    w("")

    w("\t};")
    w(f"\trootObject = {ids['project']} /* Project object */;")
    w("}")

    return "\n".join(lines)


if __name__ == "__main__":
    os.makedirs(PROJ_DIR, exist_ok=True)
    content = generate_pbxproj()
    out_path = os.path.join(PROJ_DIR, "project.pbxproj")
    with open(out_path, "w") as f:
        f.write(content)
    print(f"Generated {out_path}")
    print(f"File size: {os.path.getsize(out_path)} bytes")
