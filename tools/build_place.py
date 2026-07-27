#!/usr/bin/env python3
"""Pack the Luau sources in src/ into a single playable Roblox place file.

    python3 tools/build_place.py

Writes build/WheelieBeta.rbxlx, which Roblox Studio opens directly (File >
Open from File). src/ stays the source of truth; the .rbxlx is generated.
"""

from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "build" / "WheelieBeta.rbxlx"

# Enum.Material values used below.
MATERIAL_SMOOTH_PLASTIC = 272

_referent = 0


def next_referent() -> str:
    global _referent
    _referent += 1
    return f"RBX{_referent}"


def color3uint8(r: int, g: int, b: int) -> int:
    return (0xFF << 24) | (r << 16) | (g << 8) | b


def cdata(text: str) -> str:
    """Wrap source in CDATA, splitting any literal ]]> that would close it."""
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script_item(class_name: str, name: str, source_path: pathlib.Path) -> str:
    source = source_path.read_text(encoding="utf-8")
    return f"""<Item class="{class_name}" referent="{next_referent()}">
      <Properties>
        <string name="Name">{name}</string>
        <bool name="Disabled">false</bool>
        <ProtectedString name="Source">{cdata(source)}</ProtectedString>
      </Properties>
    </Item>"""


def cframe(x: float, y: float, z: float) -> str:
    return f"""<CoordinateFrame name="CFrame">
          <X>{x}</X><Y>{y}</Y><Z>{z}</Z>
          <R00>1</R00><R01>0</R01><R02>0</R02>
          <R10>0</R10><R11>1</R11><R12>0</R12>
          <R20>0</R20><R21>0</R21><R22>1</R22>
        </CoordinateFrame>"""


def part_item(
    class_name: str,
    name: str,
    size: tuple[float, float, float],
    position: tuple[float, float, float],
    rgb: tuple[int, int, int],
    extra: str = "",
) -> str:
    sx, sy, sz = size
    px, py, pz = position
    return f"""<Item class="{class_name}" referent="{next_referent()}">
      <Properties>
        <string name="Name">{name}</string>
        <bool name="Anchored">true</bool>
        <bool name="CanCollide">true</bool>
        <Color3uint8 name="Color3uint8">{color3uint8(*rgb)}</Color3uint8>
        {cframe(px, py, pz)}
        <token name="Material">{MATERIAL_SMOOTH_PLASTIC}</token>
        <Vector3 name="size"><X>{sx}</X><Y>{sy}</Y><Z>{sz}</Z></Vector3>
        <token name="TopSurface">0</token>
        <token name="BottomSurface">0</token>
        <token name="LeftSurface">0</token>
        <token name="RightSurface">0</token>
        <token name="FrontSurface">0</token>
        <token name="BackSurface">0</token>{extra}
      </Properties>
    </Item>"""


def service(class_name: str, children: list[str], properties: str = "") -> str:
    body = "\n    ".join(children)
    return f"""<Item class="{class_name}" referent="{next_referent()}">
    <Properties>
      <string name="Name">{class_name}</string>{properties}
    </Properties>
    {body}
  </Item>"""


def build() -> str:
    # Placeholder floor so Studio's edit view is not empty; CourseBuilder
    # replaces it (and adds the jumps) the moment the game runs.
    floor = part_item(
        "Part",
        "Floor",
        (1024, 2, 1024),
        (0, -1, 0),
        (150, 150, 152),
    )

    spawn_pad = part_item(
        "SpawnLocation",
        "SpawnPad",
        (12, 1, 12),
        (0, 1.2, 62),
        (120, 120, 122),
        extra="""
        <bool name="Enabled">true</bool>
        <bool name="Neutral">true</bool>
        <bool name="AllowTeamChangeOnTouch">false</bool>""",
    )

    workspace = service(
        "Workspace",
        [floor, spawn_pad],
        properties="""
      <bool name="FilteringEnabled">true</bool>
      <float name="Gravity">196.2</float>""",
    )

    replicated_storage = service(
        "ReplicatedStorage",
        [
            script_item("ModuleScript", "BikeConfig", SRC / "ReplicatedStorage" / "BikeConfig.luau"),
            script_item("ModuleScript", "BikeBuilder", SRC / "ReplicatedStorage" / "BikeBuilder.luau"),
            script_item("ModuleScript", "WorldBuilder", SRC / "ReplicatedStorage" / "WorldBuilder.luau"),
            script_item("ModuleScript", "RiderPose", SRC / "ReplicatedStorage" / "RiderPose.luau"),
            script_item("ModuleScript", "Ragdoll", SRC / "ReplicatedStorage" / "Ragdoll.luau"),
        ],
    )

    server_script_service = service(
        "ServerScriptService",
        [script_item("Script", "BikeServer", SRC / "ServerScriptService" / "BikeServer.server.luau")],
    )

    starter_player_scripts = service(
        "StarterPlayerScripts",
        [script_item("LocalScript", "BikeClient", SRC / "StarterPlayer" / "StarterPlayerScripts" / "BikeClient.client.luau")],
    )

    starter_player = service("StarterPlayer", [starter_player_scripts])

    lighting = service("Lighting", [])

    return f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
  {workspace}
  {lighting}
  {replicated_storage}
  {server_script_service}
  {starter_player}
</roblox>
"""


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build(), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
