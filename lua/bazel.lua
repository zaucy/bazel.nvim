local Job = require("plenary.job")
local util = require("bazel.util")

local M = {}

local DEFAULT_OPTS = {
	format_on_save = true,
}

function M.get_target_list(callback)
	local targets = {}

	local job = Job:new({
		command = "bazel",
		args = { "query", "kind('cc_(binary|test)', //...)", "--output=label_kind" },
		on_stdout = function(_, label_kind_str)
			local target = util.parse_label_kind_str(label_kind_str)
			table.insert(targets, target)
		end,
		on_exit = function(_)
			vim.schedule(function()
				callback(targets)
			end)
		end,
	})

	if callback == nil then
		return job:sync()
	end

	job:start()
end

function M.get_source_target_list(opts, callback)
	opts = opts or {}
	if opts.source_file == nil then
		opts.source_file = util.buf_rel_path(0)
	end
	local kind = ""
	if opts.kind ~= nil then
		kind = "kind('" .. opts.kind .. "') "
	end
	local targets = {}

	local bazel_query = kind .. "intersect  allrdeps(" .. opts.source_file .. ")"
	local job = Job:new({
		command = "bazel",
		args = { "query", "--infer_universe_scope", bazel_query, "--output=label_kind" },
		on_stdout = function(_, label_kind_str)
			local target = util.parse_label_kind_str(label_kind_str)
			table.insert(targets, target)
		end,
		on_exit = function(_)
			vim.schedule(function()
				callback(targets)
			end)
		end,
	})

	if callback == nil then
		return job:sync()
	end

	job:start()
end

function M.select_source_target(opts, select_ui_opts, on_choice)
	select_ui_opts = select_ui_opts or {}
	select_ui_opts = vim.tbl_deep_extend("keep", select_ui_opts, {
		prompt = "Build Target",
		format_item = function(item)
			return item.label .. " (" .. item.kind .. ")"
		end,
	})
	M.get_source_target_list(opts, function(targets)
		if next(targets) == nil then
			print("No bazel targets with source file")
			return
		end

		vim.ui.select(targets, select_ui_opts, function(target)
			on_choice(target)
		end)
	end)
end

function M.select_target(opts, on_choice)
	opts = opts or {}
	opts = vim.tbl_deep_extend("keep", opts, {
		prompt = "Build Target",
		format_item = function(item)
			return item.label .. " (" .. item.kind .. ")"
		end,
	})
	M.get_target_list(function(targets)
		vim.ui.select(targets, opts, function(target)
			on_choice(target)
		end)
	end)
end

function M.build(label)
	util.open_term({ "bazel", "build", label })
end

function M.run(label)
	util.open_term({ "bazel", "run", label })
end

function M.test(label)
	util.open_term({ "bazel", "test", label })
end

function M.source_target_run(source_file)
	M.select_source_target(
		{
			source_file = source_file,
			kind = "cc_(binary|test)",
		},
		nil,
		function(target)
			if target ~= nil then
				M.run(target.label)
			end
		end
	)
end

function M.info(keys, callback)
	keys = keys or {}

	local info_table = {}

	local args = { "info" }

	for _, key in ipairs(keys) do
		table.insert(args, key)
	end

	local job = Job:new({
		command = "bazel",
		args = args,
		on_stdout = function(_, data)
			if #keys == 1 then
				info_table[keys[1]] = data
			else
				local key_end = data:find(":")
				info_table[data:sub(0, key_end - 1)] = data:sub(key_end + 2)
			end
		end,
		on_exit = function(_)
			vim.schedule(function()
				callback(info_table)
			end)
		end,
	})

	if callback == nil then
		return job:sync()
	end

	job:start()
end

function M.target_executable_path(label, callback)
	-- bazel cquery --output=starlark --starlark:expr=target.files_to_run.executable.path //foo
	local p = ""
	local job = Job:new({
		command = "bazel",
		args = {
			"cquery",
			"--output=starlark",
			"--starlark:expr=target.files_to_run.executable.path",
			label,
		},
		on_stdout = function(_, data)
			p = p .. data
		end,
		on_exit = function(_)
			vim.schedule(function()
				callback(p)
			end)
		end,
	})

	if callback == nil then
		return job:sync()
	end

	job:start()
end

local _dap_configs = {
	["lldb-vscode"] = function(bazel_info, label, target_exec_path)
		return {
			name = label,
			type = "lldb-vscode",
			request = "launch",
			program = vim.fs.normalize(bazel_info.execution_root .. "/" .. target_exec_path),
			sourceMap = {
				{ bazel_info.execution_root, bazel_info.workspace },
			},
			debuggerRoot = bazel_info.execution_root,
			runInTerminal = true,
			stopOnEntry = false,
			args = {},
			env = function()
				local variables = {}
				for k, v in pairs(vim.fn.environ()) do
					table.insert(variables, string.format("%s=%s", k, v))
				end
				return variables
			end,
		}
	end,
	["lldb"] = function(bazel_info, label, target_exec_path)
		return {
			name = label,
			type = "lldb",
			request = "launch",
			program = vim.fs.normalize(bazel_info.execution_root .. "/" .. target_exec_path),
			sourceMap = {
				[bazel_info.execution_root] = bazel_info.workspace,
				["."] = bazel_info.workspace,
			},
			runInTerminal = true,
			stopOnEntry = false,
		}
	end,
}

function M.generate_dap_config(dap_type, label, callback)
	M.info({ "execution_root", "workspace" }, function(info)
		M.target_executable_path(label, function(target_exec_path)
			local dap_config_fn = _dap_configs[dap_type]
			if dap_config_fn == nil then
				callback(nil)
			else
				callback(dap_config_fn(info, label, target_exec_path))
			end
		end)
	end)
end

function M.setup(opt)
	opt = opt or {}
	opt = vim.tbl_deep_extend("keep", opt, DEFAULT_OPTS)
end

return M
