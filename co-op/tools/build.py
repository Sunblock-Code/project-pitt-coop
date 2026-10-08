"""Build a separate modded pack; the original game files are never modified."""
import hashlib
import pathlib
import struct
import shutil
import argparse

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description='Install the P.I.T.T. 1.0.8 co-op alpha without modifying the original game.')
parser.add_argument('game_dir', nargs='?', help='Folder containing projectpitt.exe and projectpitt.pck')
parser.add_argument('--output-root', type=pathlib.Path, default=ROOT, help=argparse.SUPPRESS)
parser.add_argument('--test-data-name', default='Project P.I.T.T. Co-op Alpha', help=argparse.SUPPRESS)
args = parser.parse_args()
game = pathlib.Path(args.game_dir).resolve() if args.game_dir else (ROOT / 'game' if (ROOT / 'game/projectpitt.pck').is_file() else ROOT)
original = game / 'projectpitt.pck'
required = ['projectpitt.pck', 'projectpitt.exe', 'libgodotsteam.windows.template_release.x86_64.dll', 'steam_api64.dll']
missing = [name for name in required if not (game / name).is_file()]
if missing:
    raise SystemExit('Game files not found: ' + ', '.join(missing) + '\nExtract the mod next to the game executable, or drag your game folder onto Install Mod.cmd.')
data = original.read_bytes()
assert data[:4] == b'GDPC'
version, major, minor, patch, flags = struct.unpack_from('<5I', data, 4)
assert version in (3, 4) and not flags & 1, 'Unsupported or encrypted pack'
base, directory = struct.unpack_from('<QQ', data, 24)
count, = struct.unpack_from('<I', data, directory)
cursor = directory + 4
files = {}
for _ in range(count):
    length, = struct.unpack_from('<I', data, cursor)
    cursor += 4
    name = data[cursor:cursor+length].rstrip(b'\0').decode()
    cursor += length
    offset, size = struct.unpack_from('<QQ', data, cursor)
    digest = data[cursor+16:cursor+32]
    entry_flags, = struct.unpack_from('<I', data, cursor+32)
    cursor += 36
    assert entry_flags == 0, name
    payload = data[base+offset:base+offset+size]
    assert hashlib.md5(payload).digest() == digest, name
    files[name] = payload

files['coop/original_splash.gdc'] = files['scripts/splash_screen.gdc']
files['coop/original_splash.gd.remap'] = b'[remap]\npath="res://coop/original_splash.gdc"\n'
files['scripts/splash_screen.gd.remap'] = b'[remap]\npath="res://coop/bootstrap.gd"\n'
files['coop/original_input.gdc'] = files['scripts/input_manager.gdc']
files['coop/original_input.gd.remap'] = b'[remap]\npath="res://coop/original_input.gdc"\n'
files['scripts/input_manager.gd.remap'] = b'[remap]\npath="res://coop/input.gd"\n'
files['coop/original_elevator.gdc'] = files['scripts/elevator.gdc']
files['coop/original_elevator.gd.remap'] = b'[remap]\npath="res://coop/original_elevator.gdc"\n'
files['scripts/elevator.gd.remap'] = b'[remap]\npath="res://coop/elevator.gd"\n'
files['coop/original_camera.gdc'] = files['scripts/main_camera.gdc']
files['coop/original_camera.gd.remap'] = b'[remap]\npath="res://coop/original_camera.gdc"\n'
files['scripts/main_camera.gd.remap'] = b'[remap]\npath="res://coop/hold_camera.gd"\n'
files['coop/original_broom.gdc'] = files['scripts/broom.gdc']
files['coop/original_broom.gd.remap'] = b'[remap]\npath="res://coop/original_broom.gdc"\n'
files['scripts/broom.gd.remap'] = b'[remap]\npath="res://coop/broom.gd"\n'
files['coop/original_upgrade_ui.gdc'] = files['scripts/upgradeUI.gdc']
files['coop/original_upgrade_ui.gd.remap'] = b'[remap]\npath="res://coop/original_upgrade_ui.gdc"\n'
files['coop/original_duck.gdc'] = files['scripts/duck.gdc']
files['coop/original_duck.gd.remap'] = b'[remap]\npath="res://coop/original_duck.gdc"\n'
files['scripts/duck.gd.remap'] = b'[remap]\npath="res://coop/duck.gd"\n'
for original, wrapper in [('press', 'press'), ('bottom_maw', 'corpse_maw'), ('gate_shutters', 'gate_shutters'), ('gambling_terminal', 'trading_terminal'), ('game_state', 'game_state'), ('save_manager', 'save_manager')]:
    files[f'coop/original_{original}.gdc'] = files[f'scripts/{original}.gdc']
    files[f'coop/original_{original}.gd.remap'] = f'[remap]\npath="res://coop/original_{original}.gdc"\n'.encode()
    files[f'scripts/{original}.gd.remap'] = f'[remap]\npath="res://coop/{wrapper}.gd"\n'.encode()
files['coop/original_controls_menu.gdc'] = files['scenes/controls_menu.gdc']
files['coop/original_controls_menu.gd.remap'] = b'[remap]\npath="res://coop/original_controls_menu.gdc"\n'
files['scenes/controls_menu.gd.remap'] = b'[remap]\npath="res://coop/controls_menu.gd"\n'
# Keep the named native base registered at its preserved path.
class_cache = '.godot/global_script_class_cache.cfg'
files[class_cache] = files[class_cache].replace(b'res://scripts/gambling_terminal.gd', b'res://coop/original_gambling_terminal.gd')
for path in (ROOT / 'co-op/src').iterdir():
    if path.suffix not in ['.gd', '.tscn']: continue
    files['coop/' + path.name] = path.read_bytes()

# Isolate all mod saves/settings from the unmodified game.
config = bytearray(files['project.binary'])
assert config[:4] == b'ECFG'
def entry(key, value):
    key = key.encode()
    raw = value.encode()
    variant = struct.pack('<II', 4, len(raw)) + raw + bytes((-len(raw)) % 4)
    return struct.pack('<I', len(key)) + key + struct.pack('<I', len(variant)) + variant
config += entry('application/config/name', args.test_data_name)
struct.pack_into('<I', config, 4, struct.unpack_from('<I', config, 4)[0] + 1)
files['project.binary'] = bytes(config)

entries = []
directory_size = 100
for name, payload in sorted(files.items()):
    encoded = ('res://' + name).encode()
    encoded += bytes((-len(encoded)) % 4)
    entries.append((encoded, payload))
    directory_size += 4 + len(encoded) + 36
offset = (directory_size + 15) & ~15
header = bytearray(b'GDPC' + struct.pack('<5I', 2, major, minor, patch, 0) + struct.pack('<Q', 0) + bytes(64) + struct.pack('<I', len(entries)))
chunks = []
for name, payload in entries:
    header += struct.pack('<I', len(name)) + name + struct.pack('<QQ', offset, len(payload)) + hashlib.md5(payload).digest() + struct.pack('<I', 0)
    padded = payload + bytes((-len(payload)) % 16)
    chunks.append(padded)
    offset += len(padded)
runtime = args.output_root / 'co-op/runtime'
runtime.mkdir(parents=True, exist_ok=True)
(args.output_root / 'co-op/logs').mkdir(parents=True, exist_ok=True)
for name in ['projectpitt.exe', 'libgodotsteam.windows.template_release.x86_64.dll', 'steam_api64.dll']:
    if not (runtime / name).exists():
        shutil.copy2(game / name, runtime / name)
if (game / 'steam_settings').is_dir() and not (runtime / 'steam_settings').exists():
    shutil.copytree(game / 'steam_settings', runtime / 'steam_settings')
out = runtime / 'projectpitt.pck'
with out.open('wb') as f:
    f.write(header)
    f.write(bytes((-len(header)) % 16))
    for chunk in chunks:
        f.write(chunk)
print(f'Built {out} ({out.stat().st_size:,} bytes)')
print('Original SHA256:', hashlib.sha256(data).hexdigest())
print('Installation complete. Run Play Co-op.cmd.')
