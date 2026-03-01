#!/usr/bin/env bats

load 'test_helper'

@test "mock_ghq: ghq list returns MOCK_GHQ_LIST" {
  mock_ghq
  run ghq list
  assert_success
  assert_output --partial "wasabi0522/yunomi"
  # verify multi-line output (3 lines separated by newlines)
  [ "${#lines[@]}" -eq 3 ]
}

@test "mock_ghq: custom list with dollar-quote syntax" {
  mock_ghq $'github.com/a/b\ngithub.com/c/d'
  run ghq list
  [ "${#lines[@]}" -eq 2 ]
  assert_line --index 0 "github.com/a/b"
  assert_line --index 1 "github.com/c/d"
}

@test "mock_ghq: ghq root returns MOCK_GHQ_ROOT" {
  MOCK_GHQ_ROOT="/tmp/test-ghq-root"
  mock_ghq
  run ghq root
  assert_output "/tmp/test-ghq-root"
}

@test "mock_hashi: hashi list outputs JSON" {
  mock_hashi
  run hashi list --json
  assert_success
  assert_output --partial '"branch":"main"'
}

@test "mock_hashi: hashi new succeeds" {
  mock_hashi
  run hashi new "test-branch"
  assert_success
}

@test "mock_git: git branch returns MOCK_GIT_BRANCHES" {
  mock_git
  run git -C /tmp/repo branch
  assert_success
  assert_output --partial "main"
}

@test "mock_git: git branch --merged returns MOCK_GIT_MERGED" {
  mock_git
  run git -C /tmp/repo branch --merged main
  assert_output --partial "main"
}

@test "mock_jq: jq returns MOCK_JQ_OUTPUT" {
  mock_jq "test-output"
  run jq '.branch' <<< '{}'
  assert_output "test-output"
}
