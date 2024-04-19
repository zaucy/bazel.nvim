vim.filetype.add({
	extension = {
		bzl = "starlark",
		star = "starlark",
		bazelrc = "bazelrc",
		["bazel.lock"] = "json",
	},
	filename = {
		BUILD = "starlark",
		["BUILD.bazel"] = "starlark",
		WORKSPACE = "starlark",
		["WORKSPACE.bazel"] = "starlark",
		["WORKSPACE.bzlmod"] = "starlark",
		BUCK = "starlark",
	},
})

local command = require("bazel.command")

vim.api.nvim_create_user_command("BazelBuild", command.bazel_build, {})
vim.api.nvim_create_user_command("BazelRun", command.bazel_run, {})
vim.api.nvim_create_user_command("BazelTest", command.bazel_test, {})
vim.api.nvim_create_user_command("BazelDebugLaunch", command.bazel_debug_launch, { nargs = "?" })
vim.api.nvim_create_user_command("BazelSourceTargetRun", command.bazel_source_target_run, {})
vim.api.nvim_create_user_command("BazelGotoLabel", command.bazel_goto_label, { nargs = "?" })
vim.api.nvim_create_user_command("BazelGotoSourceTarget", command.bazel_goto_source_target, {})
