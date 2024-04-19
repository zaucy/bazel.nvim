local Job = require("plenary.job")
local bazel = require("bazel")
local util = require("bazel.util")

local M = {}

function M.bazel_build()
	bazel.select_target(nil, function(target)
		if target ~= nil then
			bazel.build(target.label)
		end
	end)
end

function M.bazel_run()
	bazel.select_target(nil, function(target)
		if target ~= nil then
			bazel.run(target.label)
		end
	end)
end

function M.bazel_test()
	bazel.select_target(nil, function(target)
		if target ~= nil then
			bazel.run(target.label)
		end
	end)
end

function M.bazel_source_target_run()
	bazel.source_target_run()
end

function M.bazel_debug_launch(opts)
	local adapter_name = opts.args
	if not adapter_name then
		adapter_name = "lldb"
	end
	M.select_target(nil, function(target)
		if target == nil then
			return
		end

		M.generate_dap_config(adapter_name, target.label, function(config)
			if config == nil then
				print("Unsupported adapter:", adapter_name)
				return
			end
			require("dap").run(config)
		end)
	end)
end

function M.bazel_goto_source_target()
	local messages = {}
	local filename = vim.api.nvim_buf_get_name(0):gsub("\\", "/")
	local root_dir = util.bazel_root_dir(filename)

	if root_dir == nil then
		vim.notify("Cannot find bazel root directory", vim.log.levels.ERROR)
		return
	end

	local rel_filename = filename
	if rel_filename:sub(1, #root_dir) == root_dir then
		rel_filename = filename:sub(#root_dir + 2)
	end
	local bazel_query = "intersect allrdeps(" .. rel_filename .. ")"
	local job = Job:new({
		command = "bazel",
		cwd = root_dir,
		args = { "query", "--infer_universe_scope", "//...", bazel_query, "--output=streamed_jsonproto" },
		on_stdout = function(_, line)
			local msg = vim.json.decode(line)
			if msg ~= nil and msg.type == "RULE" then
				table.insert(messages, msg)
			end
		end,
		on_exit = function(_)
			vim.schedule(function()
				if #messages == 0 then
					vim.notify("No targets with file '" .. rel_filename .. "'", vim.log.levels.ERROR)
					return
				end

				if #messages == 1 then
					local file, line, col = util.parse_label_location(messages[1].rule.location)
					vim.cmd.edit(file)
					vim.api.nvim_win_set_cursor(0, { line, col })
					return
				end

				vim.ui.select(messages, {
					prompt = "Goto Bazel Target",
					format_item = function(item)
						return item.rule.name .. " (" .. item.rule.ruleClass .. ")"
					end,
				}, function(choice)
					local file, line, col = util.parse_label_location(choice.rule.location)
					vim.cmd.edit(file)
					vim.api.nvim_win_set_cursor(0, { line, col })
				end)
			end)
		end,
	})

	job:start()
end

function M.bazel_goto_label(opts)
	local label = ""
	if opts.args == nil or #opts.args == 0 then
		---@diagnostic disable-next-line: cast-local-type
		label = util.bazel_current_label_at_cursor()
		if label == nil then
			return
		end
	else
		label = opts.args
	end

	local p = ""
	local job = Job:new({
		command = "bazel",
		args = {
			"query",
			label,
			"--output=streamed_jsonproto",
		},
		on_stdout = function(_, data)
			p = p .. data
		end,
		on_exit = function(_)
			vim.schedule(function()
				local messages = vim.tbl_map(function(line)
					return vim.json.decode(line)
				end, vim.split(p, "\n"))

				if #messages == 0 then
					vim.notify("Cannot find label '" .. label .. "'", 1)
					return
				end

				for _, msg in ipairs(messages) do
					if msg.type == "RULE" then
						local file, line, col = util.parse_label_location(msg.rule.location)
						vim.cmd.edit(file)
						vim.api.nvim_win_set_cursor(0, { line, col })
					end
				end
			end)
		end,
	})

	job:start()
end

return M
