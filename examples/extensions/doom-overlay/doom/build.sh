#!/usr/bin/env bash
set -eu

DOOMGENERIC_COMMIT=dcb7a8dbc7a16ce3dda29382ac9aae9d77d21284
SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_DIRECTORY="$SCRIPT_DIRECTORY/doomgeneric"
BUILD_DIRECTORY="$SCRIPT_DIRECTORY/build"

for command in git emcc node; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "doom build: required host executable '$command' is not installed" >&2
    exit 2
  fi
done

if [ ! -d "$SOURCE_DIRECTORY/.git" ]; then
  git clone https://github.com/ozkl/doomgeneric.git "$SOURCE_DIRECTORY"
fi
git -C "$SOURCE_DIRECTORY" fetch --depth 1 origin "$DOOMGENERIC_COMMIT"
git -C "$SOURCE_DIRECTORY" checkout --detach "$DOOMGENERIC_COMMIT"

mkdir -p "$BUILD_DIRECTORY"
cp "$SCRIPT_DIRECTORY/doomgeneric_pi.c" \
  "$SOURCE_DIRECTORY/doomgeneric/doomgeneric_pi.c"

cd "$SOURCE_DIRECTORY/doomgeneric"
emcc -O2 \
  -s WASM=1 \
  -s EXPORTED_FUNCTIONS="['_doomgeneric_Create','_doomgeneric_Tick','_DG_GetFrameBuffer','_DG_GetScreenWidth','_DG_GetScreenHeight','_DG_PushKeyEvent','_malloc','_free']" \
  -s EXPORTED_RUNTIME_METHODS="['ccall','cwrap','getValue','setValue','FS']" \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s INITIAL_MEMORY=33554432 \
  -s MODULARIZE=1 \
  -s EXPORT_NAME=createDoomModule \
  -s ENVIRONMENT=node \
  -s FILESYSTEM=1 \
  -s FORCE_FILESYSTEM=1 \
  -s EXIT_RUNTIME=0 \
  -s NO_EXIT_RUNTIME=1 \
  -DDOOMGENERIC_RESX="${DOOM_RESX:-640}" \
  -DDOOMGENERIC_RESY="${DOOM_RESY:-400}" \
  -I. \
  am_map.c d_event.c d_items.c d_iwad.c d_loop.c d_main.c d_mode.c d_net.c \
  doomdef.c doomgeneric.c doomgeneric_pi.c doomstat.c dstrings.c f_finale.c \
  f_wipe.c g_game.c hu_lib.c hu_stuff.c i_cdmus.c i_input.c i_endoom.c \
  i_joystick.c i_scale.c i_sound.c i_system.c i_timer.c i_video.c icon.c \
  info.c m_argv.c m_bbox.c m_cheat.c m_config.c m_controls.c m_fixed.c \
  m_menu.c m_misc.c m_random.c memio.c p_ceilng.c p_doors.c p_enemy.c \
  p_floor.c p_inter.c p_lights.c p_map.c p_maputl.c p_mobj.c p_plats.c \
  p_pspr.c p_saveg.c p_setup.c p_sight.c p_spec.c p_switch.c p_telept.c \
  p_tick.c p_user.c r_bsp.c r_data.c r_draw.c r_main.c r_plane.c r_segs.c \
  r_sky.c r_things.c s_sound.c sha1.c sounds.c st_lib.c st_stuff.c \
  statdump.c tables.c v_video.c w_checksum.c w_file.c w_file_stdc.c \
  w_main.c w_wad.c wi_stuff.c z_zone.c dummy.c \
  -o "$BUILD_DIRECTORY/doom.js"

node --check "$BUILD_DIRECTORY/doom.js"
test -s "$BUILD_DIRECTORY/doom.wasm"
echo "doom build: wrote $BUILD_DIRECTORY/doom.js and doom.wasm"
