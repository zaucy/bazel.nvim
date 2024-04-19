local M = {}

M.BAZEL_LABEL_REGEX = vim.regex([[\(\(@\|@@\)[a-zA-Z0-9_-]*\~\?\)\?\/\/[a-zA-Z0-9_\/-]*\(:[a-zA-Z0-9_-]*\)\?]])

function M.buf_rel_path(buf)
	local abs_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
	local cwd = vim.fs.normalize(vim.loop.cwd())
	return abs_path:sub(string.len(cwd) + 2)
end

---@param loc string
function M.parse_label_location(loc)
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

function M.bazel_root_dir(filename)
	local files = vim.fs.find("MODULE.bazel", {
		upward = true,
		path = vim.fs.dirname(filename),
	})

	if #files > 0 then
		return vim.fs.dirname(files[1])
	end

	return nil
end

function M.bazel_current_label_at_cursor()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()
	local row = cursor[1]
	local label_start, label_end = M.BAZEL_LABEL_REGEX:match_str(line, row)

	if label_start == nil then
		vim.notify("Cannot find bazel label at cursor line", vim.log.levels.ERROR)
		return nil
	end

	return line:sub(label_start + 1, label_end)
end

function M.parse_label_kind_str(label_kind_str)
	local target = {
		label = "unknown",
		kind = "unknown",
	}
	local start_idx = label_kind_str:find("rule //")
	target.label = label_kind_str:sub(start_idx + 5)
	target.kind = label_kind_str:sub(0, start_idx - 2)

	return target
end

local function open_toggleterm(toggleterm, cmd)
	toggleterm.exec(cmd)
end

local function open_lazyterm(lazyterm, cmd)
	lazyterm.open(cmd, { interactive = true })
end

function M.open_term(cmd)
	local has_toggleterm, toggleterm = pcall(require, "toggleterm")
	if has_toggleterm then
		return open_toggleterm(toggleterm, cmd)
	end

	local has_lazyterm, lazyterm = pcall(require, "lazyvim.util.terminal")
	if has_lazyterm then
		return open_lazyterm(lazyterm, cmd)
	end
end

return M
