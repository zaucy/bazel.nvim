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

vim.api.nvim_create_user_command("BazelBuild", function() require("bazel.command").bazel_build() end, {})
vim.api.nvim_create_user_command("BazelRun", function() require("bazel.command").bazel_run() end, {})
vim.api.nvim_create_user_command("BazelTest", function() require("bazel.command").bazel_test() end, {})
vim.api.nvim_create_user_command("BazelDebugLaunch", function() require("bazel.command").bazel_debug_launch() end, { nargs = "?" })
vim.api.nvim_create_user_command("BazelSourceTargetRun", function() require("bazel.command").bazel_source_target_run() end, {})
vim.api.nvim_create_user_command("BazelGotoLabel", function() require("bazel.command").bazel_goto_label() end, { nargs = "?" })
vim.api.nvim_create_user_command("BazelGotoSourceTarget", function() require("bazel.command").bazel_goto_source_target() end, {})
