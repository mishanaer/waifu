#!/usr/bin/env python3
"""Local native harness. Original installed app is read-only input."""
import pathlib, plistlib, shutil, subprocess
root = pathlib.Path(__file__).resolve().parent
source = pathlib.Path('/Applications/Animates.app')
app = pathlib.Path('/Applications/Animates Dev.app')
processes = subprocess.check_output(['/bin/ps', '-axo', 'command'], text=True).splitlines()
if str(app/'Contents/MacOS/AnimatesDev') in processes:
    raise SystemExit('Quit Animates Dev before rebuilding it.')
old = root / 'Animates Dev.app'
if old.exists() and not old.is_symlink() and not app.exists(): old.rename(app)
if not app.exists():
    subprocess.run(['/usr/bin/ditto', str(source), str(app)], check=True)
info_path = app / 'Contents/Info.plist'
with info_path.open('rb') as f: info = plistlib.load(f)
info.update(CFBundleIdentifier='local.animates.playground', CFBundleName='Animates Dev', CFBundleDisplayName='Animates Dev', CFBundleExecutable='AnimatesDev', LSUIElement=False)
for key in ['SUFeedURL', 'SUPublicEDKey', 'SUEnableAutomaticChecks']:
    info.pop(key, None)
with info_path.open('wb') as f: plistlib.dump(info, f)
shutil.copyfile(root/'catalog.json', app/'Contents/Resources/PlaygroundCatalog.json')
bridge = app / 'Contents/PlugIns/UnityBridge.bundle/Contents/MacOS/UnityBridge'
subprocess.run(['/usr/bin/clang', '-arch', 'arm64', '-fobjc-arc', '-fblocks', '-dynamiclib', '-framework', 'Cocoa', '-framework', 'AVFoundation', '-o', str(bridge), str(root/'src/UnityBridge.m'), str(root/'src/DevRuntime.m'), str(root/'src/DevControls.m')], check=True)
subprocess.run(['/usr/bin/clang++', '-arch', 'arm64', '-std=c++17', '-fobjc-arc', '-framework', 'Foundation', str(root/'src/main.mm'), str(app/'Contents/Frameworks/UnityPlayer.dylib'), '-o', str(app/'Contents/MacOS/AnimatesDev')], check=True)
# Finder metadata inherited by ditto is rejected by codesign; remove only these
# non-code attributes, leaving quarantine and all system security settings alone.
for key in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
    subprocess.run(['/usr/bin/xattr', '-rd', key, str(app)], check=True)
subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app)
if not old.exists(): old.symlink_to(app, target_is_directory=True)
