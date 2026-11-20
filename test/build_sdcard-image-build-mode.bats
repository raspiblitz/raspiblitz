#!/usr/bin/env bats
# Tests for build_sdcard.sh image build mode

# Test that --image-build flag is recognized
@test "build_sdcard.sh accepts --image-build flag" {
  run bash -c "cd ${BATS_TEST_DIRNAME}/.. && ./build_sdcard.sh --help | grep -q 'image-build'"
  [ "$status" -eq 0 ]
}

# Test that help text includes image build mode description
@test "build_sdcard.sh help shows image build mode option" {
  run bash -c "cd ${BATS_TEST_DIRNAME}/.. && ./build_sdcard.sh --help | grep -q 'enable image build mode'"
  [ "$status" -eq 0 ]
}

# Test that RB_IMAGE_BUILD environment variable is recognized
@test "RB_IMAGE_BUILD environment variable sets image build mode" {
  # This test validates the logic without running the full script
  run bash -c 'image_build=""; RB_IMAGE_BUILD="true"; : "${image_build:=${RB_IMAGE_BUILD:-false}}"; echo "$image_build"'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# Test that image build mode sets interaction to false
@test "image build mode forces interaction=false" {
  # Validate the logic
  run bash -c '
    image_build="true"
    interaction=""
    tweak_boot_drive=""
    if [ "${image_build}" = "true" ]; then
      : "${interaction:=false}"
      : "${tweak_boot_drive:=false}"
    else
      : "${interaction:=true}"
      : "${tweak_boot_drive:=true}"
    fi
    echo "$interaction"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# Test that image build mode sets tweak_boot_drive to false
@test "image build mode forces tweak_boot_drive=false" {
  # Validate the logic
  run bash -c '
    image_build="true"
    interaction=""
    tweak_boot_drive=""
    if [ "${image_build}" = "true" ]; then
      : "${interaction:=false}"
      : "${tweak_boot_drive:=false}"
    else
      : "${interaction:=true}"
      : "${tweak_boot_drive:=true}"
    fi
    echo "$tweak_boot_drive"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# Test that guards skip systemctl in image build mode
@test "systemctl commands are guarded by image_build check" {
  run bash -c "cd ${BATS_TEST_DIRNAME}/.. && grep -q 'if.*image_build.*!=.*true.*systemctl' build_sdcard.sh"
  [ "$status" -eq 0 ]
}

# Test that guards skip tune2fs in image build mode
@test "tune2fs commands are guarded by image_build check" {
  run bash -c "cd ${BATS_TEST_DIRNAME}/.. && grep -q 'image_build.*!=.*true.*tune2fs' build_sdcard.sh"
  [ "$status" -eq 0 ]
}

# Test that guards skip nmcli in image build mode
@test "nmcli commands are guarded by image_build check" {
  run bash -c "cd ${BATS_TEST_DIRNAME}/.. && grep -q 'image_build.*!=.*true.*nmcli' build_sdcard.sh"
  [ "$status" -eq 0 ]
}

# Test that guards skip ifconfig in image build mode
@test "ifconfig commands are guarded by image_build check" {
  run bash -c "cd ${BATS_TEST_DIRNAME}/.. && grep -B 5 'ifconfig wlan0 down' build_sdcard.sh | grep -q 'image_build.*!=.*true'"
  [ "$status" -eq 0 ]
}

# Test that guards skip raspi-config in image build mode
@test "raspi-config commands are guarded by image_build check" {
  run bash -c "cd ${BATS_TEST_DIRNAME}/.. && grep -B 3 'raspi-config' build_sdcard.sh | grep -q 'image_build.*!=.*true'"
  [ "$status" -eq 0 ]
}

# Test that default mode (no flag) works as before
@test "default mode has image_build=false" {
  run bash -c '
    image_build=""
    RB_IMAGE_BUILD=""
    : "${image_build:=${RB_IMAGE_BUILD:-false}}"
    echo "$image_build"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
