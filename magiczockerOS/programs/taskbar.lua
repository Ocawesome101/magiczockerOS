-- magiczockerOS 3.0 - Copyright by Julian Kriete 2016-2020

-- My ComputerCraft-Forum account:
-- http://www.computercraft.info/forums2/index.php?showuser=57180

local search = fs.exists("/magiczockerOS/programs/search.lua")
-- numbers
local w = term.getSize()
local offset = 0
-- strings
local line = ""
local time = ""
local user = user or ""
-- tables
local front = {}
local list = {}
local settings = settings or {}
local window_pos = {}
-- functions
local function back_color(a,b,c)
	if term.isColor then
		term.setBackgroundColor((term.isColor() and c) or (textutils.complete and b) or a)
	end
end
local function text_color(a,b,c)
	if term.isColor then
		term.setTextColor((term.isColor() and c) or (textutils.complete and b) or a)
	end
end
local function get_time()
	if settings.clock_visible and (os.time or os.date) then
		if os.date then
			return os.date(" %"..(settings.clock_format and "H" or "I")..":%M"..(settings.clock_format and "" or " %p").." ")
		else
			local a=nil
			local b=os.time()
			if not settings.clock_format then
				a=b>11 and "PM" or "AM"
				if b>=13 then
					b=b-12
				end
			end
			local hour="0"..floor(b)
			local minute="0"..floor((b-hour)*60)
			local tmp = (not term.isColor and (get_visible("calendar") and "-" or "_") or " ")
			return tmp..hour:sub(-2)..":"..minute:sub(-2)..""..(a and " "..a or "")..tmp
		end
	else
		return ""
	end
end
local function draw_start()
	term.setCursorPos(1,1)
	if get_visible("startmenu") then
		back_color(32768,256,settings.startmenu_button_active_back or 256)
		text_color(1,1,settings.startmenu_button_active_text or 1)
	else
		back_color(1,128,settings.startmenu_button_inactive_back or 128)
		text_color(32768,1,settings.startmenu_button_inactive_text or 1)
	end
	term.write((not term.isColor and (get_visible("startmenu") and "-m-" or "_m_")) or " m ")
end
local function draw_search()
	if user~="" and search then
		term.setCursorPos(w-2,1)
		if get_visible("search") then
			back_color(32768,256,settings.search_button_active_back or 256)
			text_color(1,1,settings.search_button_active_text or 1)
		else
			back_color(1,128,settings.search_button_inactive_back or 128)
			text_color(32768,1,settings.search_button_inactive_text or 1)
		end
		term.write((not term.isColor and (get_visible("search") and "-S-" or "_S_")) or " S ")
	end
end
local function draw_items()
	term.setCursorPos(4,1)
	local tmp = w
	if not search then
		w = w + 3
	end
	local a=line:sub(1+offset,w-#time-3-(user == "" and 0 or 3)+offset)
	local b=a
	local c=false -- inject
	local d=0 -- start
	if front.pos then
		for i=front.offset-offset+1,front.offset-offset+#list[front.pos].name+2 do
			if i>0 then
				d=0 and i or d
				a=a:sub(1,i-1).."\t"..a:sub(i+1,#a)
				c=true
			end
		end
	end
	if c then
		back_color(1,128,settings.taskbar_items_inactive_back or 128)
		text_color(32768,1,settings.taskbar_items_inactive_text or 1)
		term.write(a:sub(1,a:find("\t")-1))
		back_color(32768,256,settings.taskbar_items_active_back or 256)
		text_color(1,1,settings.taskbar_items_active_text or 1)
		local found=a:find("\t")
		local last=found
		while found do
			term.write(b:sub(found,found))
			found=a:find("\t",found+1)
			if found then
				last=found
			end
		end
		back_color(1,128,settings.taskbar_items_inactive_back or 128)
		text_color(32768,1,settings.taskbar_items_inactive_text or 1)
		term.write(a:sub(last+1,#a))
	else
		back_color(1,128,settings.taskbar_items_inactive_back or 128)
		text_color(32768,1,settings.taskbar_items_inactive_text or 1)
		term.write(a)
	end
	if ({term.getCursorPos()})[1]<w-(user == "" and (-1) or 2)-#time then
		back_color(1,128,settings.taskbar_back or 128)
		local e=w-(user == "" and (-1) or 2)-#time-({term.getCursorPos()})[1]
		local f=(" "):rep(e)
		term.write(not term.isColor and ("_"):rep(e) or f)
	end
	w = tmp
end
local function set_items()
	local a=get_top_window() -- upper_window
	list=get_label()
	line=""
	front={}
	window_pos={}
	if a then
		local _width=w-#time-3-((not search or user == "") and 0 or 3)
		local b=0 -- cursor
		for i=1,#list do
			if not term.isColor then
				line=line.."_"..list[i].name.."_"
			else
				line=line.." "..list[i].name.." "
			end
			if list[i].id == a.id and a.window.get_visible() then
				front.offset=b
				front.pos=i
				if offset>b then
					offset=b
				elseif #line-offset>_width then
					offset = #line-_width
				end
			end
			for j=1,#list[i].name+2 do
				window_pos[#window_pos+1]=list[i].id
			end
			b=b+#list[i].name+2
		end
		if offset>0 and #line-offset<_width then
			offset=#line-_width
		end
		if offset<0 then
			offset=0
		end
	end
	draw_items()
end
local function draw_clock()
	time=get_time()
	if settings.clock_visible then
		if get_visible("calendar") then
			back_color(32768,256,settings.clock_back_active or 256)
			text_color(1,32768,settings.clock_text_active or 1)
		else
			back_color(1,128,settings.clock_back_inactive or 128)
			text_color(32768,1,settings.clock_text_inactive or 1)
		end
		term.setCursorPos(w+1-#time-((not search or user == "") and 0 or 3),1)
		term.write(time)
	end
end
local function set_vis(ign)
	if get_visible("contextmenu") and ign~="cm" then
		set_visible("contextmenu",false)
	end
	if get_visible("startmenu") and ign~="sm" then
		set_visible("startmenu",false)
		draw_start()
	end
	if get_visible("calendar") and ign~="ca" then
		set_visible("calendar",false)
		draw_clock()
	end
	if get_visible("search") and ign~="se" then
		set_visible("search",false)
		draw_search()
	end
end
-- start
draw_start()
set_items()
draw_search()
-- events
while true do
	local a, b, c = coroutine.yield()
	if a == "user" or a == "refresh_settings" then
		if a == "user" then
			user = user_data().name
		else
			settings = get_settings()
			if settings.clock_visible == nil then
				settings.clock_visible=true
			end
		end
		draw_clock()
		draw_start()
		draw_items()
		draw_search()
	elseif a == "mouse_click" then
		if c<4 then -- open/close start menu
			set_vis("sm")
			set_visible("startmenu",not get_visible("startmenu"))
			draw_start()
		elseif user~="" and c>=(w-(user == "" and (-1) or 2)-#time)+(search and 0 or 3) and c<(w-(user == "" and (-1) or 2))+(search and 0 or 3) then -- open/close calendar
			set_vis("ca")
			set_visible("calendar",not get_visible("calendar"))
			draw_clock()
		elseif search and user~="" and c>w-3 then -- open/close search
			set_vis("se")
			set_visible("search",not get_visible("search"))
			draw_search()
		elseif b == 1 or b == 3 then -- taskbar entries
			if b == 1 then -- left
				switch_visible(window_pos[c-3+offset])
			else -- middle
				close_window(window_pos[c-3+offset])
			end
			set_items()
			set_vis()
		end
	elseif a == "mouse_scroll" then
		if c>3 and c<=w-#time-(search and 3 or 0) then
			if b == -1 and offset>0 then
				offset=offset-1
			elseif b == 1 and #line>w-#time-3+offset then
				offset=offset+1
			end
			draw_items()
		end
	elseif a == "start_change" then
		draw_start()
	elseif a == "search_change" then
		draw_search()
	elseif a == "calendar_change" then
		draw_clock()
	elseif a == "window_change" then
		draw_start()
		set_items()
		draw_search()
	elseif a == "os_time" then
		draw_clock()
	elseif a == "term_resize" then
		w=term.getSize()
		draw_start()
		set_items()
		draw_search()
	end
end
