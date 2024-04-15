local Job = require("plenary.job")
local Path = require("plenary.path")

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

local BAZEL_LABEL_REGEX = vim.regex([[\(\(@\|@@\)[a-zA-Z0-9_-]*\~\?\)\?\/\/[a-zA-Z0-9_\/-]*\(:[a-zA-Z0-9_-]*\)\?]])

local M = {}

local function open_toggleterm(toggleterm, cmd)
	toggleterm.exec(cmd)
end

local function open_lazyterm(lazyterm, cmd)
	lazyterm.open(cmd, { interactive = true })
end

local function open_term(cmd)
	local has_toggleterm, toggleterm = pcall(require, "toggleterm")
	if has_toggleterm then
		return open_toggleterm(toggleterm, cmd)
	end

	local has_lazyterm, lazyterm = pcall(require, "lazyvim.util.terminal")
	if has_lazyterm then
		return open_lazyterm(lazyterm, cmd)
	end
end

local function parse_label_kind_str(label_kind_str)
	local target = {
		label = "unknown",
		kind = "unknown",
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
end

function M.get_target_list(callback)
	local targets = {}

	local job = Job:new({
		command = "bazel",
		args = { "query", "kind('cc_(binary|test)', //...)", "--output=label_kind" },
		on_stdout = function(_, label_kind_str)
			local target = parse_label_kind_str(label_kind_str)
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

local function buf_rel_path(buf)
	local abs_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
	local cwd = vim.fs.normalize(vim.loop.cwd())
	return abs_path:sub(string.len(cwd) + 2)
end

function M.get_source_target_list(opts, callback)
	opts = opts or {}
	if opts.source_file == nil then
		opts.source_file = buf_rel_path(0)
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
			local target = parse_label_kind_str(label_kind_str)
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
	open_term({ "bazel", "build", label })
end

function M.run(label)
	open_term({ "bazel", "run", label })
end

function M.test(label)
	open_term({ "bazel", "test", label })
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

local function bazel_source_target_run_command()
	M.source_target_run()
end

local function bazel_debug_launch_command(opts)
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

---@param loc string
local function parse_label_location(loc)
	local index = #loc
	local end_index = #loc

	while loc:sub(index, index) ~= ":" do
		index = index - 1
		if index < 0 then
			return nil, nil, nil
		end
	end

	local col = loc:sub(index + 1, end_index)
	end_index = index

	index = index - 1
	if index < 0 then
		return nil, nil, nil
	end

	while loc:sub(index, index) ~= ":" do
		index = index - 1
		if index < 0 then
			return nil, nil, nil
		end
	end

	local line = loc:sub(index + 1, end_index - 1)
	local file = loc:sub(0, index - 1)

	return file, tonumber(line), tonumber(col)
end

local function bazel_current_label_at_cursor()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()
	local row = cursor[1]
	local label_start, label_end = BAZEL_LABEL_REGEX:match_str(line, row)

	if label_start == nil then
		vim.notify("Cannot find bazel label at cursor line", vim.log.levels.ERROR)
		return nil
	end

	return line:sub(label_start + 1, label_end)
end

local function bazel_goto_label(opts)
	local label = ""
	if opts.args == nil or #opts.args == 0 then
		label = bazel_current_label_at_cursor()
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
						local file, line, col = parse_label_location(msg.rule.location)
						vim.cmd.edit(file)
						vim.api.nvim_win_set_cursor(0, { line, col })
					end
				end
			end)
		end,
	})

	job:start()
end

local function bazel_root_dir(filename)
	local files = vim.fs.find("MODULE.bazel", {
		upward = true,
		path = vim.fs.dirname(filename),
	})

	if #files > 0 then
		return vim.fs.dirname(files[1])
	end

	return nil
end

local function bazel_goto_source_target(opts)
	local messages = {}
	local filename = vim.api.nvim_buf_get_name(0):gsub("\\", "/")
	local root_dir = bazel_root_dir(filename)
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
					local file, line, col = parse_label_location(messages[1].rule.location)
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
					local file, line, col = parse_label_location(choice.rule.location)
					vim.cmd.edit(file)
					vim.api.nvim_win_set_cursor(0, { line, col })
				end)
			end)
		end,
	})

	job:start()
end

vim.api.nvim_create_user_command("BazelBuild", bazel_build_command, {})
vim.api.nvim_create_user_command("BazelRun", bazel_run_command, {})
vim.api.nvim_create_user_command("BazelTest", bazel_test_command, {})
vim.api.nvim_create_user_command("BazelDebugLaunch", bazel_debug_launch_command, { nargs = "?" })
vim.api.nvim_create_user_command("BazelSourceTargetRun", bazel_source_target_run_command, {})
vim.api.nvim_create_user_command("BazelGotoLabel", bazel_goto_label, { nargs = "?" })
vim.api.nvim_create_user_command("BazelGotoSourceTarget", bazel_goto_source_target, {})

return M
