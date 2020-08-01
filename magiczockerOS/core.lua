-- magiczockerOS 3.0 - Copyright by Julian Kriete 2016-2020

-- My ComputerCraft-Forum account:
-- http://www.computercraft.info/forums2/index.php?showuser = 57180

--[[
	run_program: Copyright (c) 2016 Jason Chu (1lann) and Bennett Anderson (GravityScore).

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the 'Software'), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
	THE SOFTWARE.
]]

local boot_logger_enabled = false
local use_old
local my_protocol = "magiczockerOS-client"
local my_computer_id = os and os.getComputerID and os.getComputerID() or nil
local modem_side
local send_id = 0
local window_messages = {}
local timers = {}
local last_timer = 0
local last_timer_exec = 0

local users = {}
local cur_user = 0

local has_errored
local error_org = error

-- variables
local coro_create = coroutine.create
local coro_resume = coroutine.resume
local coro_yield = coroutine.yield
local coro_status = coroutine.status
local last_window
local monitor_resized
local w, h = 51, 19
local change_user = {active = false}
local key_timer
local last_number = 0
local monitor_last_clicked = 0
local resize_mode = false
local running = true
local refresh_startbutton
local os_timer = 0
local cursorblink_timer
local printError = printError or nil
local user
-- tables
local drag_old = {0, 0}
local bios_to_reload = {"loadfile", "write", "print", "printError", "read"}
local events_to_break = {key = true, key_up = true, char = true, paste = true, terminate = true} -- this is for the last part from the main repeat loop and the send_event function for system windows
local supported_mouse_events = {mouse_click = true, mouse_drag = true, mouse_up = true, mouse_scroll = true, mouse_click_monitor = true, mouse_drag_monitor = true}
local total_size = {0, 0}
local system_settings = {}
local window_timers = {}
local position_to_add = {
	["left"] = {-1, 0},
	["right"] = {1, 0},
	["up"] = {0, -1},
	["down"] = {0, 1},
}
local number_to_check
local overrides
local monitor_order
local monitor_devices
local dont_use_xpcall = true -- experimental
local apis = {}
local click = {x = 0, y = 0}
local key_maps = {}
local last_click = {x = 0, y = 0, time = 0}
local screen = {}
local system_windows = {
	calendar = {need_resize = true, fs = true, x = w - 24, y = 2, w = 25, h = 9, visible = false, path = "/magiczockerOS/programs/calendar.lua", click_outside = true, bluescreen = true},
	contextmenu = {x = 1, y = 1, w = 1, h = 1, visible = false, path = "/magiczockerOS/programs/contextmenu.lua", click_outside = true, bluescreen = true},
	desktop = {need_resize = true, fs = true, x = 1, y = 2, w = w, h = h - 1, visible = true, path = "/magiczockerOS/programs/desktop.lua", click_outside = false, bluescreen = true},
	startmenu = {x = 1, y = 2, w = 1, h = 1, visible = false, path = "/magiczockerOS/programs/startmenu.lua", click_outside = true, bluescreen = true},
	taskbar = {need_resize = true, x = 1, y = 1, w = w, h = 1, visible = true, path = "/magiczockerOS/programs/taskbar.lua", click_outside = false, bluescreen = true},
	search = {need_resize = true, fs = true, x = w - 15, y = 2, w = 20, h = h - 1, visible = false, path = "/magiczockerOS/programs/search.lua", click_outside = true, bluescreen = true},
	osk = {x = 2, y = 3, w = 1, h = 1, visible = false, path = "/magiczockerOS/programs/osk.lua", click_outside = false, bluescreen = true},
}
local system_window_order = {"osk", "contextmenu", "taskbar", "calendar", "search", "startmenu", "desktop"} -- osk needs to be the first entry
local fs = fs or nil
local term = term or nil
local textutils = textutils or nil
local peripheral = peripheral or nil
if term then
	w, h = term.getSize()
end
-- functions
local function fallback_serialise(data, processed)
	local processed = processed or {}
	local seen = {}
	local to_return = ""
	if type(data) == "string" then
		return ("%q"):format( data )
	elseif type(data) == "number" or type(data) == "boolean" then
		return data
	elseif type(data) ~= "table" then
		error("Can't serialize type \"" .. type(data) .. "\"!")
	end
	for k, v in next, data do
		if not seen[k] and not processed[v] then
			processed[v] = processed[v] or type(v) == "table"
			seen[k] = true
			local _k = k
			local serialised = fallback_serialise(v, processed)
			if type(_k) == "string" then
				_k = ("%q"):format( _k )
			end
			to_return = to_return .. (#to_return == 0 and "" or ", ") .. "[" .. _k .. "]=" .. tostring(serialised)
		end
	end
	return "{" .. to_return .. "}"
end
local function _unpack(a, b)
	local b = (b or 1) + 1
	if a[b - 1] then
		return a[b - 1], _unpack(a, b)
	end
end
local function _ceil(a)
	local b = a .. ".0"
	local c = b:find("%.")
	return a > 0 and (b:sub(c + 1, c + 1) .. 0):sub(1, 1) + 0 > 0 and b:sub(1, c) + 1 or b:sub(1, c) + 0
end
local function _floor(a)
	local b = a .. ".0"
	local c = b:find("%.")
	return a < 0 and (b:sub(c + 1, c + 1) .. 0):sub(1, 1) + 0 > 0 and b:sub(1, c) - 1 or b:sub(1, c) + 0
end
local function add_timer(duration)
	last_timer = last_timer + 1
	timers[last_timer] = os.clock() + duration
	return last_timer
end
local function stop_timer(id)
	timers[id] = nil
end
local function send_message(side, receiver, content)
	if component then
		component.invoke(side, "send", receiver, 65535, serialise(content))
	elseif use_old then
		peripheral.call(side, "send", receiver, serialise(content))
	else
		peripheral.call(side, "transmit", receiver, 0, content)
	end
end
local function open_modem(modem, state)
	modem_side = modem
	apis.peripheral.set_block_modem(modem_side, os.getComputerID())
	if component then
		my_computer_id = modem
	else
		peripheral.call(modem_side, state or "open", my_computer_id) -- for receiving direct messages
	end
end
local available_sides = {"top", "bottom", "left", "right", "front", "back"}
local function search_modem()
	local side
	if component then
		for a in component.list("modem") do
			side = a
			break
		end
	else
		for i = 1, #available_sides do
			if peripheral.getType(available_sides[i]) == "modem" then
				side = available_sides[i]
				break
			end
		end
	end
	if side and #side > 0 then
		open_modem(side)
		local methods = peripheral and peripheral.getMethods(modem_side) or {}
		for i = 1, #methods do
			if methods[i] == "send" then
				use_old = true -- version 1.3
				break
			end
		end
	else
		modem_side = nil
	end
end
local function get_timer()
	local to_return
	local to_check = os.clock()
	for k, v in next, timers do
		to_return = v and v >= last_timer_exec and v <= to_check and (not to_return or v < to_return) and k or to_return
	end
	last_timer_exec = to_return and to_check or last_timer_exec
	return to_return
end
local stop_time = os.cancelTimer
local start_time = os.startTimer
local function start_timer(old, duration)
	local tmp = component and stop_timer or stop_time
	if tmp and old then
		tmp(old)
	end
	return component and add_timer and add_timer(duration) or start_time and start_time(duration)
end
local function error_message(program, message)
	if term then
		term.setBackgroundColor(32768)
		term.setTextColor(1)
		term.clear()
		term.setCursorPos(1, 1)
		term.write(program .. "\n")
	end
	running = false
	error_org(program .. ":" .. message)
end
local function resume_user(coro, ...)
	if coro and coro_status(coro) == "suspended" then
		local ok, err = coro_resume(coro, ...)
		if not ok then
			return error_org(err)
		end
	end
end
local function run_program(prog, errorhandling) -- xpcall -- copied from https://github.com/JasonTheKitten/Mimic/blob/gh-pages/lua/pre-bios.lua (2019-05-05)
	local coro = coro_create(prog)
	local ok = {coro_resume(coro)}
	while coro_status(coro) ~= "dead" do
		local args = {coro_yield()}
		ok = {coro_resume(coro, _unpack(args))}
	end
	if ok[1] then
		return true, _unpack(ok, 2)
	else
		return false, errorhandling and errorhandling(ok[2]) or ok[2]
	end
end
local function unserialise(str)
	local ok, err = (load or loadstring)("return " .. str, "core: unserialize", "t", {})
	if ok then
		local _func = dont_use_xpcall and run_program or xpcall
		local ok, result = _func(function() return ok() end, function(err) return err end)
		if ok then
			return result
		end
	end
	return err
end
local function add_to_log(a)
	if not fs or not boot_logger_enabled then
		return nil
	end
	local file = fs.open("/magiczockerOS/log.txt", "a")
	if file then
		file.write(os.time() .. " - " .. a .. "\n")
		file.close()
	end
end
local function load_api(name)
	add_to_log("Loading " .. name)
	local env = {}
	local file = fs.open("/magiczockerOS/apis/" .. name .. ".lua", "r")
	if file then
		setmetatable(env, {__index = _G})
		env.floor, env.ceil, env.unpack = _floor, _ceil, _unpack
		local content = file.readAll()
		file.close()
		local api, err = (load or loadstring)(content, "/magiczockerOS/apis/" .. name .. ".lua", nil, env)
		if api then
			if setfenv then
				setfenv(api, env)
			end
			local _func = dont_use_xpcall and run_program or xpcall
			local ok, err = _func(function() return api() end, function(err) return err end)
			if not ok then
				if err and err ~= "" then
					error(err, 0)
				end
				return nil
			end
			local api_ = {}
			for k, v in next, env do
				if k ~= "_ENV" then
					api_[k] = v
				end
			end
			apis[name] = api_
			add_to_log("Loaded " .. name .. "!")
			return true
		end
		if err and err ~= "" then
			error(err, 0)
		end
		return nil
	end
	error("/magiczockerOS/apis/" .. name .. ".lua: File not exists", 0)
end
local function gUD(id) -- get_user_data
	return users[id] or {}
end
local function draw_windows()
	if term and term.setCursorBlink then
		term.setCursorBlink(false)
	end
	screen = {}
	local a = apis.window.get_global_visible()
	apis.window.set_global_visible(false)
	for i = 1, #system_window_order do
		local temp_window = system_windows[system_window_order[i]].window
		if temp_window and temp_window.get_visible() then
			screen = temp_window.redraw(system_window_order[i] == "osk", screen, i * -1)
		end
		if system_window_order[i] == "startmenu" and gUD(cur_user).windows then
			local user_win = gUD(cur_user).windows
			for j = 1, #user_win do
				local temp_window = user_win[j].window
				if temp_window.get_visible() then
					screen = temp_window.redraw(j == 1, screen, j)
					if temp_window.get_state() == "maximized" then
						break
					end
				else
					break
				end
			end
		end
	end
	apis.window.set_global_visible(a)
	apis.window.redraw_global_cache(true)
	local tmp = system_windows.search.window
	local tmp1 = gUD(cur_user)
	if tmp and tmp.get_visible() then
		tmp.restore_cursor()
	elseif tmp1.windows and #tmp1.windows > 0 and tmp1.windows[1].window.get_visible() then
		tmp1.windows[1].window.restore_cursor()
	elseif term and term.setCursorBlink then
		term.setCursorBlink(false)
	end
end
local function get_user_id(name, server)
	local tmp = true
	local to_return = 0
	for i = 1, #users do
		if users[i].name == name and users[i].server == server then
			tmp = false
			to_return = i
			break
		end
	end
	if tmp then
		to_return = cur_user + 1
		users[to_return] = {name = name, server = server, windows = {}, labels = {}, desktop = {}, settings = {}, session_id = nil}
	end
	return to_return
end
local function load_settings(user)
	local tmpU = gUD(user)
	tmpU.settings = nil
	if tmpU then
		if tmpU.server then
			send_message(modem_side, tmpU.server, {return_id = my_computer_id, session_id = tmpU.session_id, protocol = my_protocol, username = tmpU.name, my_id = send_id, mode = "get_settings"})
			window_messages[send_id] = {0, 0}
			send_id = send_id + 1
		elseif tmpU.name and #tmpU.name > 0 then
			local file = fs.open("/magiczockerOS/users/" .. tmpU.name .. "/settings.json", "r")
			if file then
				local content = file.readAll()
				file.close()
				tmpU.settings = content and unserialise(content) or tmpU.settings
			end
		end
	end
	tmpU.settings = tmpU.settings or {}
end
local function save_user_settings(user, data)
	local tmp = gUD(user)
	if user > 0 and tmp.settings then
		if tmp.server then
			send_message(modem_side, tmp.server, {return_id = my_computer_id, session_id = tmp.session_id, protocol = my_protocol, username = tmp.name, my_id = send_id, mode = "update_settings", data = data})
			window_messages[send_id] = {0, 0}
			send_id = send_id + 1
		else
			local file = fs.open("/magiczockerOS/users/" .. tmp.name .. "/settings.json", "w")
			if file then
				file.write(fallback_serialise(data))
				file.close()
			end
		end
	end
end
local function move_windows_to_screen()
	local total_screen_size = {apis.window.get_size()}
	for _, v in next, users do
		local vv = v.windows
		for j = 1, #vv do
			local temp_window = vv[j]
			local win_x, win_y, win_w, win_h = temp_window.window.get_data("normal")
			local new_win_x = win_x > total_screen_size[1] and total_screen_size[1] or win_x
			local new_win_y = win_y > total_screen_size[2] and total_screen_size[2] or win_y
			if win_x ~= new_win_x or win_y ~= new_win_y then
				temp_window.window.reposition(new_win_x, new_win_y, win_w, win_h, "normal")
			end
			temp_window.window.reposition(1, 2, total_screen_size[1], total_screen_size[2] - 1, "maximized")
			if temp_window.window.get_visible() and temp_window.window.get_state() == "maximized" or temp_window.is_system then
				resume_user(temp_window.coroutine, "term_resize")
			end
		end
	end
end
local function resume_system(name, coro, ...)
	if coroutine.status(coro) ~= "dead" then
		local cor_system_ok, cor_system_err = coro_resume(coro, ...)
		if not cor_system_ok then
			return error_message(name, cor_system_err)
		end
	end
end
local function resize_system_windows()
	local size = {apis.window.get_size()}
	for i = 1, #system_window_order do
		local win = system_window_order[i]
		if system_windows[win].need_resize and system_windows[win].window then
			local x, y, w, h = system_windows[win].window.get_data()
			if win == "desktop" then
				w, h = size[1], size[2] - 1
			elseif win == "taskbar" then
				w = size[1]
			elseif win == "search" then
				x, h = size[1] - 19, size[2] - 1
			elseif win == "calendar" then
				x = size[1] - 24
			end
			system_windows[win].window.reposition(x, y, w, h)
			resume_system("34" .. win, system_windows[win].coroutine, "term_resize")
		end
	end
end
local function setup_monitors(...)
	monitor_resized, monitor_devices = {}, {}
	apis.window.set_devices(system_settings.monitor_mode or "normal", ...)
	monitor_order = apis.window.get_devices()
	if #monitor_order == 0 then
		return nil
	end
	for i = 1, #monitor_order do
		local name = monitor_order[i].name
		monitor_resized[name] = true
		monitor_devices[name] = i
	end
	apis.window.set_global_visible(false)
	resize_system_windows()
	move_windows_to_screen()
	apis.window.set_global_visible(true)
end
local function load_system_settings()
	local file = fs.open("/magiczockerOS/settings.json", "r")
	if file then
		local content = file.readAll()
		system_settings = content and (unserialise(content) or {}) or system_settings
		file.close()
	end
	local a = system_settings
	system_settings.monitor_mode = a.monitor_mode or "normal"
	system_settings.devices = a.devices or {"computer"}
end
local function update_windows(user)
	local user = user or cur_user
	local data = gUD(user)
	local vis_old = apis.window.get_global_visible()
	apis.window.set_global_visible(false)
	apis.window.reload_color_palette(data.settings)
	for i = 1, #system_window_order do
		local tmp = system_windows[system_window_order[i]]
		local tmp2 = tmp.filesystem
		if tmp2 then
			tmp2.set_root_path(data.server and "/" or "/magiczockerOS/users/" .. data.name .. "/files")
			tmp2.set_server(data.server)
			tmp2.is_online(data.server ~= nil)
		end
		resume_system("33" .. system_window_order[i], tmp.coroutine, "user", user, change_user.logoff)
		if data.settings then
			resume_system("32" .. system_window_order[i], tmp.coroutine, "refresh_settings")
		end
		if system_window_order[i] == "taskbar" then
			resume_system("31taskbar", system_windows.taskbar.coroutine, "window_change")
		end
	end
	for i = 1, #data.windows do
		local tmp = data.windows[i]
		tmp.window.settings(data.settings, i == 1)
		if tmp.is_system then
			resume_user(tmp.coroutine, "refresh_settings")
		end
	end
	if system_windows.osk.window then
		system_windows.osk.window.settings(data.settings, true)
	end
	apis.window.set_global_visible(vis_old)
	apis.window.clear_cache()
	draw_windows()
end
local function setup_user(username, session)
	local tmp = username:find("\\") or nil
	local name = tmp and username:sub(tmp + 1) or username
	local server = tmp and tonumber(username:sub(1, tmp - 1)) or nil
	cur_user = get_user_id(name, server)
	users[cur_user].session_id = session
	if name then
		apis.filesystem.remove_listener("/magiczockerOS/users/" .. name .. "/files/desktop")
	end
	if my_computer_id and peripheral then
		search_modem()
	else
		apis.peripheral.set_block_modem()
	end
	if server and not modem_side then
		return nil
	end
	last_window = nil
	if not session then
		if name ~= "" and fs.exists("/magiczockerOS/users/" .. name .. "/files") and not fs.isDir("/magiczockerOS/users/" .. name .. "/files") then
			fs.delete("/magiczockerOS/users/" .. name .. "/files")
		end
		if name ~= "" and not fs.exists("/magiczockerOS/users/" .. name .. "/files") then
			fs.makeDir("/magiczockerOS/users/" .. name .. "/files")
		end
		if name ~= "" and not fs.exists("/magiczockerOS/users/" .. name .. "/files/desktop") then
			fs.makeDir("/magiczockerOS/users/" .. name .. "/files/desktop")
		end
		apis.filesystem.add_listener("/magiczockerOS/users/" .. name .. "/files/desktop", {makeDir = true, open = true, delete = true})
	end
	load_settings(cur_user)
	if #gUD(cur_user).windows > 0 then
		local tmp = gUD(cur_user).windows
		for j = 1, #tmp do
			tmp[j].window.drawable(true)
		end
	end
	update_windows(cur_user)
	return true
end
local function get_remote(id, suser, environment)
	return function(server_id, func, ...)
		local user_data = gUD(id > 0 and suser or cur_user)
		send_message(modem_side, server_id, {return_id = my_computer_id, session_id = user_data.session_id, mode = "execute", protocol = my_protocol, username = user_data.name, my_id = send_id, command = func, data = {...}})
		window_messages[send_id] = {id, id > 0 and suser or nil}
		local my_id = send_id
		send_id = send_id + 1
		local timer = environment.os.startTimer(2)
		while true do
			local e = {environment.coroutine.yield()}
			if e[1] == "modem_message" and type(e[2]) == "number" then
				if e[2] == my_id then
					window_messages[send_id] = nil
					return e[3]
				end
			elseif e[1] == "timer" and e[2] == timer then
				window_messages[send_id] = nil
				return environment.error("Time out!")
			elseif e[1] == "terminate" then
				window_messages[send_id] = nil
				return environment.error("Terminated!")
			else
				environment.os.queueEvent(_unpack(e))
			end
		end
	end
end
local function create_user_window(sUser, os_root, uenv, path, ...)
	local args = {...}
	local message = ""
	local vis_old = apis.window.get_global_visible()
	last_number = last_number + 1
	local id = last_number
	local user_ = sUser or cur_user
	local user_data = gUD(user_)
	local is_remote = user_data.server
	user_data.windows = user_data.windows or {}
	table.insert(user_data.windows, 1, {id = id})
	local my_windows = user_data.windows[1]
	local path = path and "/" .. apis.filesystem.get_path(path) or nil
	local is_system_program = os_root
	if is_remote and is_system_program then
		is_remote = nil
	end
	my_windows.user = user_
	my_windows.window = apis.window.create(2, 3, 25, 10, true, true)
	my_windows.filesystem = apis.filesystem.create((#user_data.name == 0 or is_system_program or is_remote) and "/" or "/magiczockerOS/users/" .. user_data.name .. "/files", is_remote ~= nil, is_remote)
	user_data.desktop = {}
	local uenv = uenv or {}
	local env
	my_windows.contextmenu_data = nil
	my_windows.is_system = is_system_program
	apis.window.set_global_visible(false)
	local active_term = {}
	local native_term = {}
	local function set_env()
		local native_id = os.getComputerID and os.getComputerID() or 0
		env = {
			debug = debug,
			fs = {},
			multishell = {
				getCount = function() return #user_data.windows end,
				getCurrent = function() return id end,
				getFocus = function() return user_data.windows[1].id end,
				getTitle = function()
					for i = 1, #user_data.labels do
						if user_data.labels[i].id == id then
							return user_data.labels[i].name
						end
					end
				end,
				launch = function(environment, path, ...)
					if type(path) ~= "string" then
						return nil
					end
					local path = apis.filesystem.get_path(path)
					create_user_window(user_, false, environment, path, ...)
					return user_data.windows[1].id
				end,
				setFocus = function(_id)
					if _id ~= id and _id > 0 and user_data.windows[_id] then
						if resize_mode then
							resize_mode = false
							user_data.windows[1].window.toggle_border(false)
						end
						local temp_window = user_data.windows[_id]
						table.remove(user_data.windows, _id)
						table.insert(user_data.windows, 1, temp_window)
						draw_windows()
						resume_system("30taskbar", system_windows.taskbar.coroutine, "window_change")
					end
				end,
				setTitle = function(n, title)
					if type(n) == "number" and type(title) == "string" then
						title = title:gsub("\t", "")
						for i = 1, #user_data.labels do
							if user_data.labels[i].id == n then
								user_data.labels[i].name = title
								for j = 1, #user_data.windows do
									if user_data.windows[j].id == n then
										user_data.windows[j].window.set_title(title, j == 1)
										resume_system("29taskbar", system_windows.taskbar.coroutine, "window_change")
										break
									end
								end
								break
							end
						end
					end
				end,
			},
			os = {
				cancelTimer = function(n)
					if n and window_timers[n] and window_timers[n][1] == id and window_timers[n][2] == user_ then
						window_timers[n] = nil
					end
				end,
				computerID = function() return native_id end,
				computerLabel = function() return user_data.settings.computer_label or "" end,
				getComputerID = function() return native_id end,
				getComputerLabel = function() return user_data.settings.computer_label or "" end,
				setComputerLabel = function(new_label)
					user_data.settings.computer_label = new_label or user_data.settings.computer_label
					save_user_settings(user_)
				end,
				shutdown = function()
					for i = 1, #user_data.windows do
						if user_data.windows[i].id == id then
							user_data.windows[i].window.drawable(false)
							table.remove(user_data.windows, i)
							break
						end
					end
					for i = 1, #user_data.labels do
						if user_data.labels[i].id == id then
							table.remove(user_data.labels, i)
							break
						end
					end
					resume_system("28taskbar", system_windows.taskbar.coroutine, "window_change")
					draw_windows()
				end,
				version = function() return "magiczockerOS 4.0 Preview 3" end,
				queueEvent = function(...)
					os.queueEvent(id .. "", user_, ...)
				end,
				startTimer = function(nTime)
					local var = 0
					if nTime <= 0 then
						var = 1
						env.os.queueEvent("timer", 1)
					else
						var = os.startTimer(nTime)
						window_timers[var] = {id, user_}
					end
					return var
				end,
			},
			sleep = function(sTime) -- copied from bios.lua
				local timer = env.os.startTimer( sTime or 0 )
				repeat
					local _, param = env.os.pullEvent( "timer" )
				until param == timer
			end,
			unserialise = is_system_program and unserialise or nil,
			set_monitor_settings = is_system_program and function(mode, ...)
				system_settings.monitor_mode = mode or "normal"
				setup_monitors(...)
				update_windows(user_)
			end or nil,
			is_online = is_system_program and function()
				return user_data.server ~= nil
			end or nil,
			get_settings = is_system_program and function()
				return user_data.settings
			end or nil,
			save_settings = is_system_program and function(data)
				save_user_settings(user_, data)
			end or nil,
			set_settings = is_system_program and function()
				load_settings(user_)
				update_windows(user_)
			end or nil,
			reset_settings = is_system_program and function()
				if user_data.server then
					send_message(modem_side, user_data.server, {return_id = my_computer_id, session_id = user_data.session_id, protocol = my_protocol, username = user_data.name, my_id = send_id, mode = "reset_settings"})
					window_messages[send_id] = {id, user_}
					send_id = send_id + 1
					env.set_settings(user_)
					return true
				else
					local tmp = "/magiczockerOS/users/" .. user_data.name .. "/settings.json"
					if fs.exists(tmp) and not fs.isReadOnly(tmp) then
						fs.delete("/magiczockerOS/users/" .. user_data.name .. "/settings.json")
						env.set_settings(user_)
						return true
					end
					return false
				end
			end or nil,
			signin_user = is_system_program and function(server_id, user)
				send_message(modem_side, server_id, {return_id = my_computer_id, protocol = my_protocol, username = user, my_id = send_id, mode = "login"})
				window_messages[send_id] = {id, user_}
				send_id = send_id + 1
			end or nil,
			set_size = is_system_program and function(width, height)
				for i = 1, #user_data.windows do
					if user_data.windows[i].id == id then
						local _x, _y = user_data.windows[i].window.get_data()
						user_data.windows[i].window.reposition(_x, _y, width, height)
						apis.window.clear_cache()
						draw_windows()
						break
					end
				end
			end or nil,
			switch_user = is_system_program and function(logoff, username, session)
				system_windows.startmenu.window.set_visible(false)
				if system_windows.search.window then
					system_windows.search.window.set_visible(false)
				end
				if system_windows.calendar.window then
					system_windows.calendar.window.set_visible(false)
				end
				change_user = {logoff = logoff, user = username, active = true, session = session}
				os_timer = start_timer(os_timer, 0)
			end or nil,
			logout_user = is_system_program and function(username)
				if not username or user_ == username then
					return false
				end
				env.switch_user(true, username)
				return true
			end or nil,
			floor = is_system_program and _floor or nil,
			ceil = is_system_program and _ceil or nil,
			term = {},
			user = is_system_program and user_ or nil,
			user_data = is_system_program and function() return user_data end or nil,
			peripheral = apis.peripheral and apis.peripheral.create(#user_data.name == 0 or path and is_system_program or false),
			magiczockerOS = {
				contextmenu = system_windows.contextmenu.window and {
					clear_map = function() my_windows.contextmenu_data = nil end,
					add_map = function(from_x, from_y, width_x, width_y, items)
						if type(from_x) == "number" and type(width_x) == "number" and type(from_y) == "number" and type(width_y) == "number" and type(items) == "table" and width_x > 0 and width_y > 0 then
							my_windows.contextmenu_data = my_windows.contextmenu_data or {}
							local tmp = my_windows.contextmenu_data
							tmp[#tmp + 1] = {from_x, width_x, from_y, width_y, items}
							return #tmp
						end
					end,
					on_menu_key = function(no, x, y)
						if type(no) == "number" and type(x) == "number" and type(y) == "number" and my_windows.contextmenu_data and my_windows.contextmenu_data[no] then
							local _, _, win_w, win_h = my_windows.window.get_data()
							if x > 0 and y > 0 and x <= win_w and y < win_h then
								my_windows.contextmenu_on_key = my_windows.contextmenu_on_key or {data = nil, x = 0, y = 0}
								local tmp = my_windows.contextmenu_on_key
								tmp.data = my_windows.contextmenu_data[no][5]
								tmp.x = x
								tmp.y = y + 1
								return true
							end
						elseif type(no) == "nil" then
							my_windows.contextmenu_on_key = nil
						end
					end,
				},
			},
		}
		env.os.reboot = env.os.shutdown
		for k, v in next, my_windows.window do
			if term[k] or k == "setCursorBlink" then
				native_term[k] = v
				active_term[k] = v
				env.term[k] = function(...) return active_term[k](...) end
			end
		end
		env.term.getGraphicsMode = term.getGraphicsMode or nil -- CraftOS-PC support
		env.term.current = function() return active_term end
		env.term.native = type(term.native) == "function" and function() return native_term end or native_term -- before 1.6 > table; since 1.6 > function
		env.term.redirect = function(target)
			if type(target) ~= "table" then
				env.error("bad argument #1 (expected table, got " .. type(target) .. ")", 2) 
			end
			if target == term then
				env.error("term is not a recommended redirect target, try term.current() instead", 2)
			end
			for k, v in next, native_term do
				if type(k) == "string" and type(v) == "function" and type(target[k]) ~= "function" then
					target[k] = function()
						env.error("Redirect object is missing method " .. k .. ".", 2)
					end
				end
			end
			local oldRedirectTarget = active_term
			active_term = target
			return oldRedirectTarget
		end
		env.unpack = _unpack
		env.dofile = function(path)
			if env.fs.exists(path) and not env.fs.isDir(path) then
				local file = env.fs.open(path, "r")
				if file then
					local content = file.readAll()
					file.close()
					local program, err = (env.load or env.loadstring)(content, path, "t", env._G)
					if env.setfenv then
						env.setfenv(program, env._G)
					end
					if err then
						return error(err)
					end
					return program()
				end
			end
		end
		do
			local test = env
			env = uenv
			uenv = test
		end
		for k, v in next, uenv do
			env[k] = v
		end
		for k, v in next, _G do
			if not env[k] then
				env[k] = v
			end
		end
		env.os.run = function(_tEnv, path, ...)
			if type(_tEnv) ~= "table" then
				env.error("bad argument #1 (expected table, got " .. type(_tEnv) .. ")", 2) 
			end
			if type(path) ~= "string" then
				env.error("bad argument #2 (expected string, got " .. type(path) .. ")", 2) 
			end
			local title_old
			path = apis.filesystem.get_path(path)
			if not fs.exists("/rom/programs/advanced/multishell") and not fs.exists("/rom/programs/advanced/multishell.lua") then
				local name = path
				local tmp = apis.filesystem.find_in_string(name:reverse(), "/")
				if tmp then
					name = name:sub(-tmp + 1)
				end
				if name:sub(-4) == ".lua" then
					name = name:sub(1, -5)
				end
				for i = 1, #user_data.labels do
					if user_data.labels[i].id == id then
						title_old = user_data.labels[i].name
						user_data.labels[i].name = name
						for j = 1, #user_data.windows do
							if user_data.windows[j].id == id then
								user_data.windows[j].window.set_title(name:gsub("\t", ""), j == 1)
								resume_system("27taskbar", system_windows.taskbar.coroutine, "window_change")
								break
							end
						end
						break
					end
				end
			end
			local file = env.fs.open(path, "r")
			if file then
				local tEnv = _tEnv
				setmetatable(tEnv, {__index = env._G})
				local content = file.readAll()
				file.close()
				local program, err = (env.load or env.loadstring)(content, "@" .. path, "t", tEnv)
				if program then
					local args = {...}
					tEnv._ENV = tEnv
					if env.setfenv then
						env.setfenv(program, tEnv)
					end
					local _func = dont_use_xpcall and run_program or xpcall
					local ok, err = _func(function() return program(_unpack(args)) end, function(err) return err end)
					if not fs.exists("/rom/programs/advanced/multishell") and not fs.exists("/rom/programs/advanced/multishell.lua") then
						for i = 1, #user_data.labels do
							if user_data.labels[i].id == id then
								user_data.labels[i].name = title_old
								for j = 1, #user_data.windows do
									if user_data.windows[j].id == id then
										user_data.windows[j].window.set_title(title_old, j == 1)
										resume_system("26taskbar", system_windows.taskbar.coroutine, "window_change")
										break
									end
								end
								break
							end
						end
					end
					if not ok then
						if err and err ~= "" then
							env.printError(path .. ":" .. err, 0)
						end
						return nil
					end
					return true
				end
				if err and err ~= "" then
					env.printError(path .. "::" .. err, 0)
				end
				return nil
			end
			env.printError(path .. ": File not exists", 0)
		end
		for k, v in next, _G.os do
			if not env.os[k] and v then
				env.os[k] = v
			end
		end
		do
			local tmp = my_windows.filesystem
			for k in next, is_system_program and tmp or _G.fs do
				if tmp[k] then
					env.fs[k] = tmp[k]
				end
			end
		end
		-- copy bios functions to env
		for i = 1, #bios_to_reload do
			local tmp = bios_to_reload[i]
			if _G[tmp] then
				env[tmp] = (env.load or env.loadstring)(overrides[tmp] or string.dump(_G[tmp]), nil, nil, env)
				if overrides[tmp] then
					env[tmp] = env[tmp]()
				end
				if setfenv then
					setfenv(env[tmp], env)
				end
			end
		end
		env.os.loadAPI = function(path)
			path = apis.filesystem.get_path(path)
			local name = path
			local tmp = apis.filesystem.find_in_string(name:reverse(), "/")
			if tmp then
				name = name:sub(-tmp + 1)
			end
			local env2 = {}
			local file = env.fs.open(path, "r")
			if file then
				setmetatable(env2, {__index = env._G})
				local content = file.readAll()
				file.close()
				local api, err = (env.load or env.loadstring)(content, "@" .. path, "t", env2)
				if api then
					env2._ENV = env2
					if setfenv then
						setfenv(api, env2)
					end
					local _func = dont_use_xpcall and run_program or xpcall
					local ok, err = _func(function() return api() end, function(err) return err end)
					if not ok then
						if err and err ~= "" then
							env.error(path .. err)
						end
						return
					end
					local api_ = {}
					for k, v in next, env2 do
						if k ~= "_ENV" then
							api_[k] = v
						end
					end
					env[name:gsub(".lua", "")] = api_
					return true
				end
				if err and err ~= "" then
					env.error(path .. err)
				end
				return nil
			end
			env.error(path .. ": File not exists")
		end
		env._G = env
		if (_VERSION or "") == "Lua 5.1" then -- Bug fix for shell
			env._ENV = env
		end
		if not fs.exists("/rom/apis/io.lua") and fs.exists("/magiczockerOS/CC/io.lua") then -- Fix for CraftOS-PC
			local tEnv = {}
			setmetatable(tEnv, {__index = env._G})
			local file = fs.open("/magiczockerOS/CC/io.lua", "r")
			local content = file.readAll()
			file.close()
			local program = (env.load or env.loadstring)(content, "@" .. path, "t", tEnv)
			if program then
				if env.setfenv then
					env.setfenv(program, tEnv)
				end
			end
			if program then
				local _func = dont_use_xpcall and run_program or xpcall
				local ok = _func(function() return program() end, function(err) return err end)
				if ok then
					env.io = {}
					for k, v in next, tEnv do
						if k ~= "_ENV" then
							env.io[k] = v
						end
					end
				end
			end
		elseif not fs.exists("/rom/apis") and io then -- io-Fix for MC 1.0 and higher without apis-folder
			env.io = {}
			for k, v in next, io do
				if type(v) == "function" then
					env.io[k] = (env.load or env.loadstring)(string.dump(v), nil, nil, env)
					if setfenv then
						setfenv(env.io[k], env)
					end
				end
			end
		end
		if type(os.unloadAPI) == "function" then
			env.os.unloadAPI = (env.load or env.loadstring)(string.dump(os.unloadAPI), nil, nil, env)
			if setfenv then
				setfenv(env.os.unloadAPI, env)
			end
		end
		-- load apis to env
		if fs.isDir("/rom/apis/") then
			local blacklist = {peripheral = true, settings = true, color = true, colours = true, keys = true, multishell = true, term = true}
			for _, v in next, fs.list("/rom/apis/") do
				if not blacklist[v:gsub(".lua", "")] and not fs.isDir("/rom/apis/" .. v) then
					env.os.loadAPI("/rom/apis/" .. v)
				end
			end
		end
		if not path then
			env.shell = nil
		end
	end
	path = path or "/rom/programs/shell"
	if fs.exists(path .. ".lua") then
		path = path .. ".lua"
	end
	if path:sub(1, 1) ~= "/" then
		path = "/" .. path
	end
	set_env()
	do
		local name = path
		local tmp = apis.filesystem.find_in_string(name:reverse(), "/")
		if tmp then
			name = name:sub(-tmp + 1)
		end
		if name:sub(-4) == ".lua" then
			name = name:sub(1, -5)
		end
		user_data.labels[#user_data.labels + 1] = {id = id, name = name}
		resume_system("25taskbar", system_windows.taskbar.coroutine, "window_change")
		my_windows.window.settings(user_data.settings, true)
		my_windows.window.set_title(name, true)
	end
	my_windows.filesystem.set_remote(get_remote(id, user_, env))
	local file = os_root and fs.open(path, "r") or path and env.fs.open(path, "r")
	local program, err, content
	if file then
		content = file.readAll()
		file.close()
	elseif not is_system_program or is_remote and path then
		content = "local tmp = fs.open(\"" .. path .. "\", \"r\")\nif tmp then\n(load or loadstring)(tmp.readAll(), \"" .. path .. "\", nil, _G)()\nelse\nerror(\"File not exists\")\nend"
	else
		message = "File not exists"
	end
	do
		if content then
			program, err = (env.load or env.loadstring)(content, "@" .. path, "t", env)
		end
		if program then
			env._ENV = env
			if setfenv then
				setfenv(program, env)
			end
		else
			if err and err ~= "" then
				message = err or "D:"
			else
				message = "Unknown error"
			end
		end
	end
	local function wait_error()
		if env.term.setBackgroundColor then
			env.term.setBackgroundColor(32768)
		end
		if env.term.setTextColor then
			env.term.setTextColor(1)
		end
		env.term.clear()
		env.term.setCursorPos(1, 1)
		env.print(message)
		env.print("Press any key to continue")
		local _running = true
		repeat
			local e = {coroutine.yield()}
			if e[1] == "key" then
				_running = false
			end
		until not _running
		return false
	end
	local function kill_window()
		for i = #user_data.windows, 1, -1 do
			if my_windows.id == user_data.windows[i].id then
				if i == 1 then
					resize_mode = false
				end
				for j = 1, #user_data.labels do
					if user_data.labels[j].id == user_data.windows[i].id then
						table.remove(user_data.labels, j)
						break
					end
				end
				table.remove(user_data.windows, i)
			end
		end
		user_data.desktop = {}
		resume_system("24taskbar", system_windows.taskbar.coroutine, "window_change")
		draw_windows()
	end
	my_windows.coroutine = coroutine.create(
		function()
			if #message > 0 then
				wait_error()
				kill_window()
			else
				local _func = dont_use_xpcall and run_program or xpcall
				local ok, err = _func(function() return program(_unpack(args)) end, function(err) return err end)
				if not ok then
					if err and err ~= "" then
						message = err
					else
						message = "unknown error"
					end
					wait_error()
				end
				kill_window()
			end
		end
	)
	resume_user(my_windows.coroutine, "term_resize")
	if vis_old then
		apis.window.set_global_visible(true)
		draw_windows()
	end
end
local function create_system_windows(i)
	local env
	local message = ""
	local temp = system_window_order[i]
	local path = system_windows[temp].path
	local window_number = temp
	add_to_log("Starting " .. temp)
	system_windows[temp].contextmenu_data = nil
	system_windows[temp].id = i * -1
	system_windows[temp].filesystem = system_windows[temp].fs and apis.filesystem.create("/") or nil
	system_windows[temp].window = apis.window.create(system_windows[temp].x, system_windows[temp].y, system_windows[temp].w, system_windows[temp].h, system_windows[temp].visible, temp == "osk")
	if temp == "osk" then
		system_windows[temp].window.set_title("On-Screen Keyboard", true)
	end
	env = {
		fs = system_windows[temp].filesystem or fs,
		native_fs = fs,
		close_os = function() running = false end,
		close_window = function(id)
			local uData = gUD(cur_user)
			uData.desktop = {}
			for i = 1, #uData.windows do
				if uData.windows[i].id == id then
					table.remove(uData.windows, i)
					break
				end
			end
			local tmp = uData.labels
			for i = 1, #tmp do
				if tmp[i].id == id then
					table.remove(tmp, i)
					break
				end
			end
			if temp ~= "taskbar" then
				resume_system("23taskbar", system_windows.taskbar.coroutine, "window_change")
			end
			draw_windows()
		end,
		create_window = function(path, root, env, ...)
			create_user_window(cur_user, root, env, path, ...)
		end,
		get_label = function() return gUD(cur_user).labels or {} end,
		get_settings = function() return gUD(cur_user).settings end,
		get_top_window = function() local uData = gUD(cur_user) return uData.windows and uData.windows[1] or nil end,
		get_user = function() return cur_user end,
		get_visible = function(name) return system_windows[name].window and system_windows[name].window.get_visible() or false end,
		set_size = function(width, height, not_redraw)
			local _x, _y = system_windows[window_number].window.get_data()
			system_windows[window_number].window.reposition(_x, _y, width, height)
			apis.window.clear_cache()
			if not not_redraw then
				draw_windows()
			end
		end,
		set_pos = function(posx, posy, not_redraw)
			local _, _, _w, _h = system_windows[window_number].window.get_data()
			system_windows[window_number].window.reposition(posx, posy, _w, _h)
			apis.window.clear_cache()
			if not not_redraw then
				draw_windows()
			end
		end,
		get_total_size = function() return total_size[1], total_size[2] end,
		set_visible = function(name, state)
			if system_windows[name].window then
				system_windows[name].window.set_visible(state)
				refresh_startbutton = true
				draw_windows()
			end
		end,
		settings = gUD(cur_user).settings,
		show_desktop = function()
			system_windows[window_number].window.set_visible(false)
			local uData = gUD(cur_user)
			if #uData.windows > 0 then
				local tmpd = uData.desktop
				if #tmpd == 0 then
					for i = 1, #uData.windows do
						if uData.windows[i].window.get_visible() then
							uData.windows[i].window.set_visible(false)
							tmpd[#tmpd + 1] = i
						end
					end
				else
					for i = 1, #tmpd do
						uData.windows[tmpd[i]].window.set_visible(true)
					end
					uData.desktop = {}
				end
			end
			resume_system("22taskbar", system_windows.taskbar.coroutine, "window_change")
			draw_windows()
		end,
		switch_user = function(logoff, username, session)
			system_windows[window_number].window.set_visible(false)
			change_user = {logoff = logoff, user = username, active = true, session = session}
			os.queueEvent("timer", os_timer)
		end,
		send_event = function(e, ...)
			if system_windows.search.window and system_windows.search.window.get_visible() or system_windows.startmenu.window.get_visible() or system_windows.calendar.window and system_windows.calendar.window.get_visible() then
				local prog = system_windows.search.window and system_windows.search.window.get_visible() and "search" or system_windows.startmenu.window.get_visible() and "startmenu" or "calendar"
				resume_system("21" .. prog, system_windows[prog].coroutine, e, ...)
			else
				local uData = gUD(cur_user)
				for j = 1, #uData.windows do
					local temp_window = uData.windows[j]
					if temp_window.window.get_visible() then
						resume_user(temp_window.coroutine, e, ...)
						if events_to_break[e] then
							break
						end
					end
				end
			end
		end,
		switch_visible = function(id)
			local uData = gUD(cur_user)
			uData.desktop = {}
			for i = 1, #uData.windows do
				if uData.windows[i].id == id then
					local visible = uData.windows[i].window.get_visible()
					if i == 1 and visible then
						local temp_window = uData.windows[1]
						uData.windows[i].window.set_visible(not visible)
						table.remove(uData.windows, 1)
						uData.windows[#uData.windows + 1] = temp_window
					else
						local temp_window = uData.windows[i]
						table.remove(uData.windows, i)
						table.insert(uData.windows, 1, temp_window)
						uData.windows[1].window.set_visible(true)
					end
					break
				end
			end
			draw_windows()
		end,
		term = system_windows[temp].window,
		resume_system = resume_system,
		user = cur_user,
		user_data = function() return gUD(cur_user) end,
		unpack = _unpack,
		floor = _floor,
		ceil = _ceil,
		magiczockerOS = {
			contextmenu = system_windows.contextmenu.window and {
				clear_map = function() system_windows[temp].contextmenu_on_key = nil system_windows[temp].contextmenu_data = nil end,
				add_map = function(from_x, from_y, width_x, width_y, items)
					if type(from_x) == "number" and type(width_x) == "number" and type(from_y) == "number" and type(width_y) == "number" and type(items) == "table" and width_x > 0 and width_y > 0 then
						system_windows[temp].contextmenu_data = system_windows[temp].contextmenu_data or {}
						local tmp = system_windows[temp].contextmenu_data
						tmp[#tmp + 1] = {from_x, width_x, from_y, width_y, items}
						return #tmp
					end
				end,
				on_menu_key = function(no, x, y)
					if type(no) == "number" and type(x) == "number" and type(y) == "number" and system_windows[temp].contextmenu_data and system_windows[temp].contextmenu_data[no] then
						local _, _, win_w, win_h = system_windows[temp].window.get_data()
						if x > 0 and y > 0 and x <= win_w and y <= win_h then
							system_windows[temp].contextmenu_on_key = system_windows[temp].contextmenu_on_key or {data = nil, x = 0, y = 0}
							local tmp = system_windows[temp].contextmenu_on_key
							tmp.data = system_windows[temp].contextmenu_data[no][5]
							tmp.x = x
							tmp.y = y
							return true
						end
					elseif type(no) == "nil" then
						system_windows[temp].contextmenu_on_key = nil
					end
				end,
			},
		},
	}
	if system_windows[temp].filesystem then
		env.os = {
			startTimer = function(nTime)
				local var = 0
				if nTime <= 0 then
					var = 1
					env.os.queueEvent("timer", 1)
				else
					var = os.startTimer(nTime)
					window_timers[var] = {system_windows[temp].id, nil}
				end
				return var
			end,
			queueEvent = function(...)
				os.queueEvent(system_windows[temp].id .. "", "", ...)
			end,
		}
		system_windows[temp].filesystem.set_remote(get_remote(system_windows[temp].id, nil, env))
	end
	setmetatable(env, {__index = _G})
	for k, v in next, _G.os do
		if not env.os[k] and v then
			env.os[k] = v
		end
	end
	if print then
		env.print = (env.load or env.loadstring)(overrides.print or string.dump(_G.print), nil, nil, env)
		if overrides.print then
			env.print = env.print()
		end
		if setfenv then
			setfenv(env.print, env)
		end
	end
	if printError then
			env.printError = (env.load or env.loadstring)(overrides.printError or string.dump(_G.printError), nil, nil, env)
			if overrides.printError then
				env.printError = env.printError()
			end
			if setfenv then
				setfenv(env.printError, env)
			end
		end
	local file = fs.open(path, "r")
	local program, err
	if file then
		local content = file.readAll()
		file.close()
		program, err = (load or loadstring)(content, path, nil, env)
		if program then
			if setfenv then
				setfenv(program, env)
			end
		else
			if err and err ~= "" then
				message = err
			else
				message = "unknown error"
			end
		end
	else
		message = "File not exists"
	end
	local function wait_error()
		if system_windows[temp].bluescreen then
			error_org(message or "D:")
		end
		if env.term.setBackgroundColor then
			env.term.setBackgroundColor(32768)
		end
		if env.term.setTextColor then
			env.term.setTextColor(1)
		end
		env.term.clear()
		env.term.setCursorPos(1, 1)
		env.print(message)
		env.print("Press any key to continue")
		local _running = true
		repeat
			local e = {coroutine.yield()}
			if e[1] == "key" then
				_running = false
			end
		until not _running
		return false
	end
	system_windows[temp].coroutine = coroutine.create(
		function()
			if #message > 0 then
				wait_error()
			else
				local _func = dont_use_xpcall and run_program or xpcall
				local ok, err = _func(function() return program() end, function(err) return err end)
				if not ok then
					if err and err ~= "" then
						message = err
					else
						message = "unknown error"
					end
					wait_error()
				end
			end
		end
	)
	resume_system("20" .. temp, system_windows[temp].coroutine, "")
	add_to_log("Finished " .. temp)
end
local function load_bios()
	add_to_log("Loading bios...")
	overrides = {}
	local function_list = {
		["read"] = true,
		["print"] = true,
		["printError"] = true,
		["loadfile"] = true,
		["write"] = true,
	}
	local start
	local function check_expect_path(path)
		if not _G["~expect"] and fs.exists(path) and not fs.isDir(path) then
			local file = fs.open(path, "r")
			if file then
				local content = file.readAll() or ""
				file.close()
				_G["~expect"] = (load or loadstring)(content, "@expect.lua")().expect -- Fixed 2020-01-03
			end
		end
	end
	check_expect_path("/rom/modules/main/craftos/expect.lua")
	-- https://github.com/SquidDev-CC/CC-Tweaked/commit/93310850d27286919c162d2387d6540430e2cbe6
	check_expect_path("/rom/modules/main/cc/expect.lua")
	if _G["~expect"] then
		local file = fs.open("/magiczockerOS/CCTweaked/bios.lua", "r")
		if file then
			for line in file.readLine do
				local tmp = line:sub(1, 9) == "function " and line:find("%(") and line:sub(10, ({line:find("%(")})[1] - 1)
				if tmp and function_list[tmp] then
					start = tmp
					overrides[start] = "local function dummy" .. line:sub(({line:find("%(")})[2])
					overrides[start] = overrides[start] .. "\nlocal expect = _ENV[\"~expect\"]"
				elseif start then
					overrides[start] = overrides[start] .. "\n" .. line
					if line == "end" then
						overrides[start] = overrides[start] .. "\nreturn dummy"
						start = nil
					end
				end
			end
			file.close()
		end
	end
	add_to_log("Loaded bios!")
end
local function load_keys()
	if #(_HOST or "") > 1 then -- Filter from https://forums.coronalabs.com/topic/71863-how-to-find-the-last-word-in-string/
		number_to_check = tonumber(({_HOST:match("%s*(%S+)$"):reverse():sub(2):reverse():gsub("%.", "")})[1] or "")
	end
	if number_to_check and type(number_to_check) == "number" and number_to_check >= 1132 then -- GLFW
		key_maps[67] = "c"
		key_maps[77] = "m"
		key_maps[78] = "n"
		key_maps[82] = "r"
		key_maps[83] = "s"
		key_maps[84] = "t"
		key_maps[88] = "x"
		key_maps[262] = "right"
		key_maps[263] = "left"
		key_maps[264] = "down"
		key_maps[265] = "up"
		key_maps[345] = "right_ctrl"
		key_maps[348] = "context_menu"
	else -- LWJGL
		key_maps[19] = "r"
		key_maps[20] = "t"
		key_maps[31] = "s"
		key_maps[45] = "x"
		key_maps[46] = "c"
		key_maps[49] = "n"
		key_maps[50] = "m"
		key_maps[56] = "context_menu"
		key_maps[157] = "right_ctrl"
		key_maps[200] = "up"
		key_maps[203] = "left"
		key_maps[205] = "right"
		key_maps[208] = "down"
	end
end
-- start
load_keys()
load_system_settings()
load_api("filesystem")
load_api("peripheral")
load_api("window")
apis.window.set_peripheral(apis.peripheral.create(true))
if not term then
	term = {isColor = function() return true end}
--	term = apis.peripheral.get_device(apis.peripheral.get_devices(true, true, "monitor")[1])
end
setup_monitors(_unpack(system_settings.devices or {}))
apis.window.set_global_visible(false)
load_bios()
do
	local contextm = 0
	for i = #system_window_order, 1, -1 do
		if not fs.exists(system_windows[system_window_order[i]].path) then
			table.remove(system_window_order, i)
		end
	end
	for i = 1, #system_window_order do
		if system_window_order[i] == "contextmenu" then
			contextm = i
		end
	end
	if contextm > 0 then
		create_system_windows(contextm)
	end
	for i = #system_window_order, 1, -1 do
		if i ~= contextm then
			create_system_windows(i)
		end
	end
end
resize_system_windows()
add_to_log("Starting user")
do
	local tmp = fs.exists("/magiczockerOS/programs/login.lua")
	local tmp_user = tmp and "" or fs.list("/magiczockerOS/users/")[1]
	if setup_user(tmp_user) then -- "1\\"
		if tmp then
			create_user_window(cur_user, true, nil, "/magiczockerOS/programs/login.lua")
		end
	end
end
add_to_log("Loaded user")
os_timer = start_timer(os_timer, 0)
if not term.setCursorBlink then
	cursorblink_timer = start_timer(cursorblink_timer, 0.5)
end
if not textutils or not textutils.serialize or not textutils.unserialize then
	textutils = textutils or {}
	textutils.serialize = textutils.serialize or fallback_serialise
	textutils.serialise = textutils.serialize
	textutils.unserialize = textutils.unserialize or unserialise
	textutils.unserialise = textutils.unserialize
end
add_to_log("DRAW WINDOWS!")
apis.window.set_global_visible(true)
draw_windows()
-- events
local _yield = computer and computer.pullSignal or coroutine.yield
local ton = tonumber
if component then
	computer.pushSignal("timer_health")
end
repeat
	local e = {_yield()}
	local timer
	if e[1] == "timer_health" then
		timer = get_timer()
		if timer then
			stop_timer(timer)
		end
	elseif e[1] == "drag" and drag_old and drag_old[1] == e[3] and drag_old[2] == e[4] then
		e[1] = nil
	end
	if e[1] == "key_down" then
		e[1] = "key"
		e[2] = e[4]
	elseif e[1] == "touch" then
		if monitor_devices[e[2]] then
			e[1] = "monitor_touch"
		else
			e[1] = "mouse_click"
			e[2] = e[5] + 1
		end
	elseif e[1] == "drag" then
		if monitor_devices[e[2]] then
			e[1] = "monitor_touch"
		else
			e[1] = "mouse_drag"
			e[2] = e[5] + 1
		end
	elseif e[1] == "scroll" then
		e[1] = "mouse_scroll"
		e[2] = e[5] * -1
	elseif e[1] == "screen_resized" then
		--e[1] = "term_resize"
	end
	local user_data = gUD(cur_user)
	if monitor_devices.computer and user_data.settings and user_data.settings.mouse_left_handed and (e[1] == "mouse_click" or e[1] == "mouse_drag" or e[1] == "mouse_up") then
		e[2] = e[2] == 1 and 2 or e[2] == 2 and 1 or e[2]
	end
	if monitor_devices.computer and (e[1] == "mouse_click" or e[1] == "mouse_drag") and (system_settings.monitor_mode or "normal") == "extend" then
		e[3] = e[3] + monitor_order[monitor_devices.computer].offset
	end
	if supported_mouse_events[e[1]] then
		if not monitor_devices.computer and e[1] ~= "mouse_click_monitor" and e[1] ~= "mouse_drag_monitor" and e[1] ~= "mouse_scroll" then
			e[1] = nil
		else
			total_size[1], total_size[2] = apis.window.get_size()
		end
	end
	if (e[1] == "mouse_drag" and monitor_devices.computer or e[1] == "mouse_drag_monitor") and (click.x ~= e[3] or click.y ~= e[4]) and e[4] <= total_size[2] and e[3] <= total_size[1] and last_window and last_window.window and last_window.window.get_visible() then
		drag_old[1], drag_old[2] = e[3], e[4]
		local has_changed = false
		local tmp_window = last_window
		local t_id = last_window.id
		if tmp_window then
			apis.window.set_global_visible(false)
			local win_x, win_y, win_w, win_h = tmp_window.window.get_data()
			local w_old, h_old = win_w, win_h
			if tmp_window.window.has_header() and win_y == click.y then
				if resize_mode then
					resize_mode = false
					tmp_window.window.toggle_border(false)
				end
				win_x = win_x + e[3] - click.x
				win_y = e[4] < 2 and 2 or e[4]
				if t_id < 0 and e[4] == 1 then
					has_changed = true
					click.y = 2
					click.x = e[3]
					tmp_window.window.reposition(win_x, 2, win_w, win_h, "normal")
				elseif t_id > 0 and e[4] == 1 then
					if tmp_window.window.get_state() ~= "maximized" then
						tmp_window.window.set_state("maximized")
						resume_user(tmp_window.coroutine, "term_resize")
						has_changed = true
					end
					click.x = e[3]
					click.y = 2
				elseif t_id > 0 and tmp_window.window.get_state() == "maximized" then
					tmp_window.window.set_state("normal")
					win_x, win_y, win_w, win_h = tmp_window.window.get_data()
					if win_x > e[3] or win_x + win_w - 1 < e[3] then
						win_x = _ceil(e[3] - win_w * 0.5)
					end
					tmp_window.window.reposition(win_x, e[4], win_w, win_h)
					win_y = e[4]
					resume_user(tmp_window.coroutine, "term_resize")
					has_changed = true
				else
					tmp_window.window.reposition(win_x, win_y, win_w, win_h)
				end
				if e[4] > 1 then
					click.x = e[3]
					click.y = win_y
					has_changed = true
				end
			elseif resize_mode and t_id > 0 then
				if click.x == win_x + win_w - 1 then -- border right
					win_w = e[3] - win_x + 1
					if win_w < 10 then
						win_w = 10
					end
					tmp_window.window.reposition(win_x, win_y, win_w, win_h)
					click.x = win_x + win_w - 1
				elseif click.x == win_x then -- border left
					local org_w = win_x + win_w - 1
					win_x = win_x + e[3] - click.x
					win_w = win_w - e[3] + click.x
					tmp_window.window.reposition(win_x, win_y, win_w, win_h)
					if win_w < 10 then
						win_w = 10
						win_x = org_w - win_w + 1
					end
					click.x = win_x
				end
				if click.y == win_y + win_h - 1 then -- border bottom
					win_h = e[4] - win_y + 1
					if win_h < 5 then
						win_h = 5
					end
					tmp_window.window.reposition(win_x, win_y, win_w, win_h)
					click.y = win_y + win_h - 1
				end
				if w_old ~= win_w or h_old ~= win_h then
					resume_user(tmp_window.coroutine, "term_resize")
					has_changed = true
				end
			else
				has_changed = true
				if t_id < 0 then
					resume_system("19" .. system_window_order[tmp_window.id * -1], tmp_window.coroutine, "mouse_drag", e[2], e[3] - win_x + 1, e[4] - win_y)
				else
					resume_user(tmp_window.coroutine, "mouse_drag", e[2], e[3] - win_x + 1, e[4] - win_y)
				end
			end
			apis.window.set_global_visible(true)
		end
		if has_changed then
			draw_windows()
		end
	elseif e[1] == "peripheral_detach" and e[2] == modem_side then
		search_modem()
	elseif e[1] == "rednet_message" and use_old then
		os.queueEvent("modem_message", nil, my_computer_id, nil, unserialise(e[3]))
	elseif e[1] == "monitor_touch" then
		if monitor_devices[e[2]] and monitor_order[monitor_devices[e[2]]] then
			os.queueEvent(os.clock() - monitor_last_clicked <= 0.4 and "mouse_drag_monitor" or "mouse_click_monitor", user_data.settings and user_data.settings.mouse_left_handed and 2 or 1, e[3] + monitor_order[monitor_devices[e[2]]].offset, e[4])
			monitor_last_clicked = os.clock()
		end
	elseif e[1] == "double_click" then
		if #user_data.windows > 0 and user_data.windows[1].window.get_visible() then
			local temp_window = user_data.windows[1].window
			local win_x, win_y, win_w = temp_window.get_data()
			if e[3] >= win_x and e[3] < win_x + win_w and e[4] == win_y then
				temp_window.set_state(temp_window.get_state() == "normal" and "maximized" or "normal")
				apis.window.set_global_visible(false)
				resume_user(user_data.windows[1].coroutine, "term_resize")
				apis.window.set_global_visible(true)
				draw_windows()
			end
		end
	elseif e[1] == "key" and (key_maps[e[2]] or "") == "right_ctrl" and (not term or not term.isColor or not term.isColor()) then
		key_timer = start_timer(key_timer, 0.2)
		if system_windows.startmenu.window.get_visible() then
			system_windows.startmenu.window.set_visible(false)
			resume_system("18taskbar", system_windows.taskbar.coroutine, "start_change")
			draw_windows()
		end
	elseif e[1] == "key" and (key_maps[e[2]] or "") == "context_menu" and system_windows.contextmenu.window and not system_windows.contextmenu.window.get_visible() then
		local my_window
		local co_window
		local need_redraw
		apis.window.set_global_visible(false)
		for i = 1, #system_window_order do
			if system_windows[system_window_order[i]].window.get_visible() then
				my_window = system_windows[system_window_order[i]]
				co_window = my_window.contextmenu_on_key
				if co_window then
					break
				end
			end
			if system_window_order[i] == "startmenu" and #user_data.windows > 0 and user_data.windows[1].window.get_visible() then
				my_window = user_data.windows[1]
				co_window = my_window.contextmenu_on_key
				if co_window then
					break
				end
			end
		end
		if co_window then
			total_size[1], total_size[2] = apis.window.get_size()
			local win_x, win_y = my_window.window.get_data()
			resume_system("17contextmenu", system_windows.contextmenu.coroutine, "set_data", co_window.data, win_x - 1 + co_window.x, win_y - 1 + co_window.y, my_window)
			resume_system("16contextmenu", system_windows.contextmenu.coroutine, "redraw_items")
			system_windows.contextmenu.window.set_visible(true)
			need_redraw = true
		end
		apis.window.set_global_visible(true)
		if need_redraw then
			draw_windows()
		end
	elseif e[1] == "key" and key_timer and key_maps[e[2]] then
		local _key = key_maps[e[2]]
		local temp_window = user_data.windows[1] and user_data.windows[1].window or nil
		if _key == "r" and temp_window and temp_window.get_visible() then -- maximize/resize window
			if resize_mode then
				resize_mode = false
				user_data.windows[1].window.toggle_border(false)
			end
			temp_window.set_state(temp_window.get_state() == "normal" and "maximized" or "normal")
			apis.window.set_global_visible(false)
			resume_user(user_data.windows[1].coroutine, "term_resize")
			apis.window.set_global_visible(true)
			draw_windows()
		elseif _key == "x" or _key == "t" and system_windows.calendar.window or _key == "s" and system_windows.search.window then -- open/close startmenu, calender/clock, search
			if not ((_key == "t" or _key == "s") and cur_user == 0) then
				if resize_mode then
					resize_mode = false
					user_data.windows[1].window.toggle_border(false)
				end
				local sys_window = system_windows
				if sys_window.search.window then
					sys_window.search.window.set_visible(_key == "s")
				end
				if sys_window.calendar.window then
					sys_window.calendar.window.set_visible(_key == "t")
				end
				sys_window.startmenu.window.set_visible(_key == "x")
				resume_system("15taskbar", sys_window.taskbar.coroutine, _key == "x" and "start_change" or _key == "t" and "calender_change" or "search_change")
				draw_windows()
			end
		elseif _key == "c" and temp_window and temp_window.get_visible() then -- close window
			for i = 1, #user_data.labels do
				if user_data.labels[i].id == user_data.windows[1].id then
					resize_mode = false
					table.remove(user_data.labels, i)
					break
				end
			end
			table.remove(user_data.windows, 1)
			draw_windows()
		elseif _key == "n" and cur_user > 0 then -- new window
			create_user_window(cur_user)
		elseif _key == "m" and temp_window and temp_window.get_visible() then -- minimize window
			temp_window.set_visible(false)
			local a = user_data.windows[1]
			table.remove(user_data.windows, 1)
			user_data.windows[#user_data.windows+1] = a
			resume_system("32taskbar", system_windows.taskbar.coroutine, "window_change")
			draw_windows()
		elseif position_to_add[_key] and temp_window.get_visible() and temp_window then -- move window
			local pos_x, pos_y, win_w, win_h = temp_window.get_data()
			local has_changed
			pos_x = pos_x + position_to_add[_key][1]
			pos_y = pos_y + position_to_add[_key][2]
			if pos_y < 2 then
				pos_y = 2
			end
			if pos_x > 0 and pos_x <= w and pos_y > 1 and pos_y <= h then
				if pos_y == 2 and temp_window.get_state() == "normal" then
					temp_window.set_state("maximized")
					has_changed = true
				elseif pos_y > 2 and temp_window.get_state() == "maximized" then
					temp_window.set_state("normal")
					has_changed = true
				end
				if temp_window.get_state() == "normal" then
					pos_x, pos_y, win_w, win_h = temp_window.get_data()
					pos_x = pos_x + position_to_add[_key][1]
					if not has_changed then
						pos_y = pos_y + position_to_add[_key][2]
					end
					temp_window.reposition(pos_x, pos_y, win_w, win_h)
				end
				if has_changed then
					apis.window.set_global_visible(false)
					resume_user(user_data.windows[1].coroutine, "term_resize")
					apis.window.set_global_visible(true)
				end
				draw_windows()
			end
		end
		key_timer = nil
	elseif (monitor_devices.computer and (e[1] == "mouse_click" or e[1] == "mouse_up" or e[1] == "mouse_scroll") or e[1] == "mouse_click_monitor") and screen[e[4]] and screen[e[4]][e[3]] and e[4] <= total_size[2] and e[3] <= total_size[1] then
		drag_old[1] = 0
		drag_old[2] = 0
		last_window = nil
		if e[1] == "mouse_click_monitor" then
			e[1] = "mouse_click"
		end
		if e[1] == "mouse_click" then
			click = {x = e[3], y = e[4]}
		end
		local need_redraw
		local id = screen[e[4]][e[3]]
		local cur_window = id > 0 and user_data.windows[id] or system_windows[system_window_order[id * -1]]
		if cur_window then
			local temp_window = cur_window.window
			local win_x, win_y, win_w, win_h = temp_window.get_data()
			if id ~= 1 and resize_mode then
				user_data.windows[1].window.toggle_border(false)
			end
			if e[1] == "mouse_click" and id > 1 then
				if resize_mode then
					resize_mode = false
					user_data.windows[1].window.toggle_border(false)
				end
				local temp_window = user_data.windows[id]
				table.remove(user_data.windows, id)
				table.insert(user_data.windows, 1, temp_window)
				id = 1
				need_redraw = true
				resume_system("14taskbar", system_windows.taskbar.coroutine, "window_change")
			end
			if e[1] == "mouse_click" and e[4] == win_y and cur_window.window.has_header() then
				if last_click.x == e[3] and last_click.y == e[4] and os.clock() - last_click.time < (user_data.settings.mouse_double_click_speed or 0.2) then
					os.queueEvent("double_click", e[2], e[3], e[4])
				end
				last_click.x = e[3]
				last_click.y = e[4]
				last_click.time = os.clock()
				if e[3] == win_x then -- close window
					if id == 1 then
						local tmp = user_data.labels
						for i = 1, #tmp do
							if tmp[i].id == cur_window.id then
								resize_mode = false
								table.remove(tmp, i)
								break
							end
						end
						table.remove(user_data.windows, 1)
						resume_system("13taskbar", system_windows.taskbar.coroutine, "window_change")
					elseif id < 0 then
						temp_window.set_visible(false)
						need_redraw = true
					end
					need_redraw = true
				elseif id > 0 and e[3] == win_x + 1 then -- minimize window
					temp_window.set_visible(false)
					local a = user_data.windows[id]
					table.remove(user_data.windows, id)
					user_data.windows[#user_data.windows+1] = a
					resume_system("12taskbar", system_windows.taskbar.coroutine, "window_change")
					need_redraw = true
				elseif id > 0 and e[3] == win_x + 2 then -- maximize window
					temp_window.set_state(temp_window.get_state() == "normal" and "maximized" or "normal")
					resume_user(user_data.windows[1].coroutine, "term_resize")
					need_redraw = true
				elseif id > 0 and e[3] == win_x + win_w - 1 and temp_window.get_state() == "normal" then -- resize
					resize_mode = not resize_mode
					temp_window.toggle_border(resize_mode)
				else
					last_window = cur_window
				end
			elseif e[1] == "mouse_click" and id == 1 and resize_mode and (e[3] == win_x or e[3] == win_x - 1 + win_w or e[4] == win_y - 1 + win_h) then
				last_window = cur_window
			elseif e[1] == "mouse_click" and resize_mode and e[3] > win_x and e[3] < win_x + win_w - 1 and e[4] > win_y and e[4] < win_y + win_h - 1 then
				resize_mode = false
				temp_window.toggle_border(false)
			elseif e[1] == "mouse_scroll" and (id < 0 or id == 1 or user_data.settings.mouse_inactive_window_scroll ~= false) then
				resume_user(cur_window.coroutine, e[1], e[2], e[3] - win_x + 1, e[4] - win_y + (cur_window.window.has_header() and 0 or 1))
			elseif (id == 1 or id < 0) and not resize_mode then
				last_window = cur_window
				local tmp = false
				local tmp_ = cur_window.contextmenu_data
				if e[2] == 2 and tmp_ then
					local tmpcord = {e[3] - win_x + 1, e[4] - win_y + 1}
					for i = #tmp_, 1, -1 do
						if tmpcord[1] >= tmp_[i][1] and tmpcord[1] <= tmp_[i][1] + tmp_[i][2] - 1 and tmpcord[2] >= tmp_[i][3] and tmpcord[2] <= tmp_[i][3] + tmp_[i][4] - 1 then
							tmp = true
							resume_system("11contextmenu", system_windows.contextmenu.coroutine, "set_data", tmp_[i][5], e[3], e[4], cur_window)
							resume_system("10contextmenu", system_windows.contextmenu.coroutine, "redraw_items")
							system_windows.contextmenu.window.set_visible(true)
							need_redraw = true
							break
						end
					end
				end
				if not tmp then
					if id > 0 then
						resume_user(cur_window.coroutine, e[1], e[2], e[3] - win_x + 1, e[4] - win_y + (cur_window.window.has_header() and 0 or 1))
					else
						resume_system("9" .. system_window_order[cur_window.id * -1], cur_window.coroutine, e[1], e[2], e[3] - win_x + 1, e[4] - win_y + (cur_window.window.has_header() and 0 or 1))
					end
				end
			end
			if e[1] == "mouse_click" and id ~= (system_windows.osk.id or 0) and id ~= system_windows.taskbar.id then
				local _taskbar = {search = "search", startmenu = "start", calendar = "calendar"}
				for i = 1, #system_window_order do
					local tmp = system_windows[system_window_order[i]]
					if id * -1 ~= i and tmp.window and tmp.click_outside and tmp.window.get_visible() then
						tmp.window.set_visible(false)
						if _taskbar[system_window_order[i]] then
							resume_system("8taskbar", system_windows.taskbar.coroutine, _taskbar[system_window_order[i]] .. "_change")
						end
						need_redraw = true
					end
				end
			end
			if need_redraw then
				draw_windows()
			end
		end
	elseif e[1] == "mouse_drag" or e[1] == "mouse_click" or e[1] == "mouse_up" or e[1] == "mouse_scroll" or e[1] == "mouse_click_monitor" then
	elseif e[1] == "timer" and e[2] == os_timer then
		if change_user.active then
			for j = 1, #user_data.windows do
				user_data.windows[j].window.drawable(false)
			end
			if change_user.logoff then
				users[cur_user] = nil
			end
			setup_user(change_user.user, change_user.session)
			change_user.active = false
		end
		if refresh_startbutton then
			refresh_startbutton = false
			resume_system("7taskbar", system_windows.taskbar.coroutine, "window_change")
		end
		resume_system("6taskbar", system_windows.taskbar.coroutine, "os_time")
		local tmp = system_windows.search.window
		if tmp and tmp.get_visible() then
			tmp.restore_cursor()
		elseif #user_data.windows > 0 and user_data.windows[1].window.get_visible() then
			user_data.windows[1].window.restore_cursor()
		elseif term.setCursorBlink then
			term.setCursorBlink(false)
		end
		os_timer = start_timer(os_timer, 0.5)
	elseif e[1] == "timer" and e[2] == cursorblink_timer then
		local tmp = system_windows.search.window
		if tmp and tmp.get_visible() then
			tmp.toggle_cursor_blink()
		elseif user_data.windows[1] then
			user_data.windows[1].window.toggle_cursor_blink()
		end
		cursorblink_timer = start_timer(cursorblink_timer, 0.5)
	elseif e[1] == "timer" then
		local tmp = window_timers
		if tmp[e[2]] and tmp[e[2]][1] > 0 then
			local tmpu = gUD(tmp[e[2]][2])
			local tmp1 = tmpu.windows or {}
			for i = 1, #tmp1 do
				if tmp1[i].id == tmp[e[2]][1] then
					resume_user(tmp1[i].coroutine, _unpack(e))
					tmp[e[2]] = nil
					break
				end
			end
		elseif tmp[e[2]] and tmp[e[2]][1] < 0 then
			local tmp_ = system_window_order[tmp[e[2]][1] * -1]
			resume_system("5" .. tmp_, system_windows[tmp_].coroutine, _unpack(e))
			tmp[e[2]] = nil
		end
	elseif e[1] == "modem_message" then
		if type(e[5]) == "string" then
			e[5] = textutils.unserialise(e[5])
		end
		local data = e[5]
		if type(data) == "table" then
			local tmp = window_messages[data.my_id] or nil
			if tmp and tmp[1] < 0 and tmp[2] == nil then
				tmp[1] = tmp[1] * -1
			end
			if tmp and tmp[1] > 0 and tmp[2] and gUD(tmp[2]) then
				local tmp1 = gUD(tmp[2]).windows
				for i = 1, #tmp1 do
					if tmp1[i].id == tmp[1] then
						resume_user(tmp1[i].coroutine, e[1], data.my_id, data.data and _unpack(data.data) or nil)
						tmp[e[2]] = nil
						break
					end
				end
			elseif tmp and tmp[1] > 0 and tmp[2] == nil then
				if system_windows[system_window_order[tmp[1]]] then
					resume_system("4" .. system_window_order[tmp[1]], system_windows[system_window_order[tmp[1]]].coroutine, e[1], data.my_id, data.data and _unpack(data.data) or nil)
				end
			elseif tmp and tmp[1] == 0 and data.mode == "get_settings-answer" then
				window_messages[data.my_id] = nil
				for k, v in next, users do
					if v.name == data.username and v.server == data.return_id then
						local tmp = gUD(k).settings
						for k, v in next, data.data do
							tmp[k] = v
						end
						update_windows(k)
					end
				end
			end
		end
	elseif type(ton(e[1])) == "number" then
		local _id = ton(e[1])
		local _user = e[2]
		if _id > 0 and gUD(_user) then
			local tmp = gUD(_user).windows
			for i = 1, #tmp do
				if tmp[i].id == _id then
					table.remove(e, 1)
					table.remove(e, 1)
					resume_user(tmp[i].coroutine, _unpack(e))
					break
				end
			end
		elseif _id < 0 then
			table.remove(e, 1)
			table.remove(e, 1)
			resume_system("3" .. system_window_order[_id * -1], system_windows[system_window_order[_id * -1]].coroutine, _unpack(e))
		end
	elseif e[1] == "term_resize" then
		if term and term.getSize then
			w, h = term.getSize()
		else
			w, h = nil, nil
		end
		if not w then
			w, h = 51, 19
		end
		setup_monitors(_unpack(system_settings.devices or {}))
		apis.window.set_global_visible(false)
		resize_system_windows()
		apis.window.set_global_visible(true)
		draw_windows()
	elseif e[1] == "monitor_resize" and monitor_devices[e[2]] then
		if monitor_resized and monitor_resized[e[2]] then
			monitor_resized[e[2]] = nil
		else
			setup_monitors(_unpack(system_settings.devices or {}))
			draw_windows()
		end
	elseif e[1] == "peripheral" and (apis.peripheral.get_type(e[2]) or "") == "monitor" then
	elseif e[1] == "peripheral_detach" and monitor_devices[e[2]] then
		for i = 1, #system_settings.devices do
			if system_settings.devices[i] == e[2] then
				for _ = i, #system_settings.devices - 1 do
					system_settings.devices[i] = system_settings.devices[i + 1]
				end
				system_settings.devices[#system_settings.devices] = nil
				break
			end
		end
		setup_monitors(_unpack(system_settings.devices or {}))
		draw_windows()
	elseif e[1] == "filesystem_changed" then
		if e[3] == "/magiczockerOS/users/" .. user_data.name .. "/files/desktop" then
			resume_system("2desktop", system_windows.desktop.coroutine, "term_resize")
		end
	elseif e[1] and not resize_mode then
		for i = 1, #system_window_order do
			local temp_window = system_windows[system_window_order[i]]
			if temp_window.window.get_visible() then
				local _status = coroutine.status(temp_window.coroutine)
				local continue = (system_window_order[i] == "desktop" and user_data.windows[1] and user_data.windows[1].window and not user_data.windows[1].window.get_visible()) or 
				(system_window_order[i] == "desktop" and not user_data.windows[1]) or 
				system_window_order[i] ~= "desktop"
				if continue and (_status == "normal" or _status == "suspended") then
					resume_system("1" .. system_window_order[i], temp_window.coroutine, _unpack(e))
				elseif continue and events_to_break[e[1]] and system_window_order[i] ~= "desktop" and system_window_order[i] ~= "taskbar" then
					break
				end
			end
			if system_window_order[i] == "startmenu" and #user_data.windows > 0 then
				for j = 1, #user_data.windows do
					local temp_window = user_data.windows[j]
					if temp_window.window.get_visible() then
						resume_user(temp_window.coroutine, _unpack(e))
						if events_to_break[e[1]] then
							break
						end
					end
				end
			end
		end
	end
	if computer then
		if timer then
			computer.pushSignal("timer", timer)
			computer.pushSignal("timer_health")
		elseif e[1] == "timer_health" then
			computer.pushSignal("timer_health")
		end
	end
until not running
if not has_errored then
	if term.setBackgroundColor then
		term.setBackgroundColor(32768)
	end
	if term.setTextColor then
		term.setTextColor(1)
	end
	term.clear()
	if term.setCursorBlink then
		term.setCursorBlink(true)
	end
	term.setCursorPos(1, 1)
end
