#!/system/bin/sh
MODDIR=${0%/*}
SELF_MOUNT=false
[ -f "$MODDIR/skip_mount" ] && SELF_MOUNT=true

NOMOUNT_BIN="/data/adb/modules/nomount/bin/nm"
HAVE_NM=false
if [ -d "/data/adb/modules/nomount" ] && [ -x "$NOMOUNT_BIN" ] && \
   "$NOMOUNT_BIN" version >/dev/null 2>&1; then
  HAVE_NM=true
fi

ns_mount() {
  if [ "$HAVE_NM" = true ] && "$NOMOUNT_BIN" rule add "$2" "$1" >/dev/null 2>&1; then
    return 0
  fi

  if nsenter -t 1 -m -- mount -o bind "$1" "$2" 2>/dev/null; then
    return 0
  fi
  mount -o bind "$1" "$2"
}

mount_effect_lib() {
  local target_dir="$1"
  local source_dir="$2"
  local work_dir="$MODDIR/work_mount$target_dir"

  [ -d "$target_dir" ] || return 0
  [ -f "$source_dir/libv4a_re.so" ] || return 0
  [ -f "$target_dir/libv4a_re.so" ] && return 0

  if [ "$HAVE_NM" = true ]; then
    chcon --reference="$target_dir" "$source_dir/libv4a_re.so" 2>/dev/null
    if ns_mount "$source_dir/libv4a_re.so" "$target_dir/libv4a_re.so"; then
      return 0
    fi
  fi

  [ -d "$work_dir" ] && rm -rf "$work_dir"
  mkdir -p "$work_dir"
  cp -af "$target_dir"/* "$work_dir/" 2>/dev/null
  cp -f "$source_dir/libv4a_re.so" "$work_dir/libv4a_re.so"
  chcon -R --reference="$target_dir" "$work_dir" 2>/dev/null
  ns_mount "$work_dir" "$target_dir"
}

mount_config() {
  local original="$1"
  local module_path="$2"

  [ -f "$original" ] || return 0
  [ -f "$module_path" ] || return 0
  cmp -s "$original" "$module_path" && return 0
  ns_mount "$module_path" "$original"
}

kill_audio_procs() {
  for proc in audioserver audiohalservice; do
    local pids
    pids=$(ps -A 2>/dev/null | grep "$proc" | grep -v grep | awk '{ if ($1 ~ /^[0-9]+$/) print $1; else if ($2 ~ /^[0-9]+$/) print $2 }')
    for pid in $pids; do
      kill "$pid" 2>/dev/null
    done
  done
}

if [ "$SELF_MOUNT" = true ]; then
  for arch in lib lib64; do
    mount_effect_lib "/vendor/$arch/soundfx" "$MODDIR/system/vendor/$arch/soundfx"
    mount_effect_lib "/system/$arch/soundfx" "$MODDIR/system/$arch/soundfx"
  done

  for original in $(find /odm /system /vendor -type f \( -name 'audio_effects*.conf' -o -name 'audio_effects*.xml' \) 2>/dev/null); do
    case "$original" in
      /vendor/*) module_path="$MODDIR/system$original" ;;
      *) module_path="$MODDIR$original" ;;
    esac
    mount_config "$original" "$module_path"
  done

  kill_audio_procs
fi
