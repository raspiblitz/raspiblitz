#!/usr/bin/env bats

@test "APT baseline holds back a new kernel ABI dependency" {
  run python3 "$BATS_TEST_DIRNAME/kernel_upgrade_solver.py" KernelUpgradeSolver.test_baseline_holds_new_abi
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "Production upgrade commands consume a new kernel ABI dependency" {
  run python3 "$BATS_TEST_DIRNAME/kernel_upgrade_solver.py" KernelUpgradeSolver.test_production_consumes_new_abi
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "APT upgrade does not remove packages to resolve new dependencies" {
  run python3 "$BATS_TEST_DIRNAME/kernel_upgrade_solver.py" KernelUpgradeSolver.test_no_removals_for_conflicting_dependency
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "APT upgrade respects a held kernel metapackage" {
  run python3 "$BATS_TEST_DIRNAME/kernel_upgrade_solver.py" KernelUpgradeSolver.test_respects_package_hold
  echo "$output"
  [ "$status" -eq 0 ]
}
