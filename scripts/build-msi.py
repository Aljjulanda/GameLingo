"""Create a per-user MSI from the PyInstaller onedir build using WiX 3.14."""
import hashlib
import os
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
dist, wix, output = [Path(p).resolve() for p in sys.argv[1:4]]
ns = "http://schemas.microsoft.com/wix/2006/wi"
ET.register_namespace("",ns)
def node(parent,name,**attrs):
    return ET.SubElement(parent,"{"+ns+"}"+name,attrs)
def ident(prefix,path):
    return prefix+hashlib.sha256(path.as_posix().lower().encode()).hexdigest()[:24]
def guid(s):
    return str(uuid.uuid5(uuid.NAMESPACE_URL,"https://gamelingo.local/windows/"+s))
root=ET.Element("{"+ns+"}Wix")
product=node(root,"Product",Id=guid("product/0.4.1"),Name="GameLingo Desktop",Language="1033",
             Version="0.4.1",Manufacturer="GameLingo",UpgradeCode=guid("upgrade"))
node(product,"Package",InstallerVersion="500",Compressed="yes",InstallScope="perUser",InstallPrivileges="limited",Platform="x64")
node(product,"MajorUpgrade",DowngradeErrorMessage="A newer version of GameLingo is installed.")
compression=os.environ.get("GAMELINGO_CAB_COMPRESSION","mszip")
if compression not in {"mszip","none"}:
    raise ValueError("Use mszip or none for GAMELINGO_CAB_COMPRESSION")
node(product,"MediaTemplate",EmbedCab="yes",CompressionLevel=compression)
directory=node(product,"Directory",Id="TARGETDIR",Name="SourceDir")
local=node(directory,"Directory",Id="LocalAppDataFolder")
programs=node(local,"Directory",Id="Programs",Name="Programs")
app=node(programs,"Directory",Id="INSTALLFOLDER",Name="GameLingo")
node(directory,"Directory",Id="DesktopFolder")
node(directory,"Directory",Id="ProgramMenuFolder")
feature=node(product,"Feature",Id="Application",Title="GameLingo Desktop",Level="1")
dirs={Path("."):app}
for path in sorted(dist.rglob("*")):
    rel=path.relative_to(dist)
    dest=dirs[rel.parent]
    if path.is_dir():
        dirs[rel]=node(dest,"Directory",Id=ident("d",rel),Name=path.name);continue
    cid=ident("c",rel)
    comp=node(dest,"Component",Id=cid,Guid=guid(rel.as_posix().lower()),Win64="yes")
    fil=node(comp,"File",Id=ident("f",rel),Source=str(path),Name=path.name)
    node(comp,"RegistryValue",Root="HKCU",Key="Software\\GameLingo\\Installer",Name=cid,Value="1",Type="integer",KeyPath="yes")
    if rel.as_posix()=="GameLingo.exe":
        for folder in ("DesktopFolder","ProgramMenuFolder"):
            node(fil,"Shortcut",Id="GameLingo"+folder,Directory=folder,Name="GameLingo",Advertise="no",WorkingDirectory="INSTALLFOLDER",Icon="AppIcon")
    node(feature,"ComponentRef",Id=cid)
node(product,"Icon",Id="AppIcon",SourceFile=str(dist/"_internal"/"GameLingo.ico"))
node(product,"Property",Id="ARPPRODUCTICON",Value="AppIcon")
node(product,"UIRef",Id="WixUI_InstallDir")
node(product,"Property",Id="WIXUI_INSTALLDIR",Value="INSTALLFOLDER")
build=output.parent/"msi-intermediate"
build.mkdir(parents=True,exist_ok=True)
source=build/"package.wxs";obj=build/"package.wixobj"
ET.ElementTree(root).write(source,encoding="utf-8",xml_declaration=True)
subprocess.run([wix/"candle.exe","-nologo","-out",obj,source],check=True)
subprocess.run([wix/"light.exe","-nologo","-sval","-ext","WixUIExtension","-dWixUILicenseRtf="+str(Path(__file__).with_name("installer.rtf")),
                "-spdb","-out",output,obj],check=True)

