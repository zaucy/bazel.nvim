local Job = require 'plenary.job'

local toggleterm = require("toggleterm")

local M = {}

local function parse_label_kind_str(label_kind_str)
	local target = {
		label = 'unknown',
		kind = 'unknown',
	}
	local start_idx = label_kind_str:find("rule //")
	target.label = label_kind_str:sub(start_idx + 5)
	target.kind = label_kind_str:sub(0, start_idx - 2)

	return target
end

local DEFAULT_OPTS = {
	format_on_save = true,
}

function M.setup(opt)
	opt = opt or {}
	opt = vim.tbl_deep_extend("keep", opt, DEFAULT_OPTS)

	if opt.format_on_save then
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = vim.api.nvim_create_augroup("BazelBufWritePre", { clear = true }),
			pattern = { "*.bazel", "*.bzl", "WORKSPACE", "BUILD" },
			callback = function(data)
				local cursor_pos = vim.api.nvim_win_get_cursor(0)
				local output = vim.fn.systemlist("buildifier", data.buf)

				if vim.v.shell_error == 0 then
					vim.api.nvim_buf_set_lines(data.buf, 0, -1, false, output)
				else
					for _, line in ipairs(output) do
						print(line)
					end
				end

				vim.api.nvim_win_set_cursor(0, cursor_pos)
			end,
		})
	end

end

function M.get_target_list(callback)
	local targets = {}

	local job = Job:new {
		command = "bazel",
		args = { "query", "kind('cc_(binary|test)', //...)", "--output=label_kind" },
		on_stdout = function(_, label_kind_str)
			local target = parse_label_kind_str(label_kind_str)
			table.insert(targets, target)
		end,
		on_exit = function(_)
			vim.schedule(function() callback(targets) end)
		end,
	}

	if callback == nil then
		return job:sync()
	end

	job:start()
end

function M.select_target(opts, on_choice)
	opts = opts or {}
	opts = vim.tbl_deep_extend("keep", opts, {
		prompt = "Build Target",
		format_item = function(item)
			return item.label .. ' (' .. item.kind .. ')'
		end
	})
	M.get_target_list(function(targets)
		vim.ui.select(
			targets,
			opts,
			function(target)
				on_choice(target)
			end
		)
	end)
end

function M.build(label)
	toggleterm.exec("bazel build " .. label)
end

function M.run(label)
	toggleterm.exec("bazel run " .. label)
end

function M.test(label)
	toggleterm.exec("bazel test " .. label)
end

local function bazel_build_command()
	M.select_target(nil, function(target)
		if target ~= nil then
			M.build(target.label)
		end
	end)
end

local function bazel_run_command()
	M.select_target(nil, function(target)
		if target ~= nil then
			M.run(target.label)
		end
	end)
end

local function bazel_test_command()
	M.select_target(nil, function(target)
		if target ~= nil then
			M.run(target.label)
		end
	end)
end

vim.api.nvim_create_user_command("BazelBuild", bazel_build_command, {})
vim.api.nvim_create_user_command("BazelRun", bazel_run_command, {})
vim.api.nvim_create_user_command("BazelTest", bazel_test_command, {})

return M
