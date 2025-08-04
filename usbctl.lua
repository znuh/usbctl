#!/usr/bin/env lua

--[[
 * Copyright (C) 2023 Benedikt Heinz <Zn000h AT gmail.com>
 *
 * This is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This code is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this code.  If not, see <http://www.gnu.org/licenses/>.
 */
]]--

local socket  = require "socket"
local lgi     = require "lgi"
local GObject = lgi.GObject
local GLib    = lgi.GLib
local Gio     = lgi.Gio
local Gdk     = lgi.Gdk
local Gtk     = lgi.Gtk

local ports = {
	{"1", {"4-3.3",   "3-3.3"   } },
	{"2", {"4-3.2",   "3-3.2"   } },
	{"3", {"4-3.1",   "3-3.1"   } },
	{"4", {"4-3.4.3", "3-3.4.3" } },
	{"5", {"4-3.4.2", "3-3.4.2" } },
	{"6", {"4-3.4.1", "3-3.4.1" } },
	{"7", {"4-3.4.4", "3-3.4.4" } },
}

local status_label = {}
local port_speed   = {}

local idx_label_style    = 'size="x-large"'
local status_label_style = 'size="x-large"'
local status_width       = 64

local spinner = nil
local busy    = 0

function uhubctl_done()
	busy = busy - 1
	--print("done",busy)
	if busy == 0 then
		spinner:stop()
	end
end

function cmd(path, cmd)
	local hub, port = path:match("^(%g+)%.(%d+)$")
	--print(cmd,hub,port)
	local flags   = Gio.SubprocessFlags.STDOUT_SILENCE -- set to 0 for debug
	busy = busy + 1
	spinner:start()
	local uhubctl = assert(Gio.Subprocess.new(
		{"uhubctl", "-N", "-a", cmd, "-l", hub, "-p", port},
		flags)
	)
	uhubctl:wait_async(nil, uhubctl_done)
end

function mklabel(label, speed)
	local colors = {
		[1.5]  = 'background="#ababab" foreground="#000000"', -- LS
		[12]   = 'background="#00559a" foreground="#ffffff"', -- FS
		[480]  = 'background="#c33134" foreground="#ffffff"', -- HS
		[5000] = 'background="#34adee" foreground="#ffffff"', -- SS
	}
	local col = ''
	if string.match(speed, "^%d+") then
		speed = speed + 0
		col   = colors[math.min(speed, 5000)] or ""
		if speed >= 1000 then
			speed = speed/1000 .. "G"
		else
			speed = speed .. "M"
		end
	end
	local bg = col:match('background="(%S+)"') or ""
	label:override_background_color(0, Gdk.RGBA.parse(bg))
	label.label = '<span '..status_label_style.." "..col..'><b>'..speed..'</b></span> '
end

function get_port_speed(path)
	local prefix = "/sys/bus/usb/devices/"
	local file   = prefix..path.."/speed"
	local speed  = nil
	local fh     = io.open(file,"r")
	--print(file, fh)
	if fh then
		speed = fh:read("*l")
		fh:close()
	end
	return speed
end

function update_ports()
	for idx,v in ipairs(ports) do
		local paths = v[2]
		local speed = nil

		for _,path in ipairs(paths) do
			speed = get_port_speed(path)
			if speed ~= nil then break end
		end

		speed = speed or "nc"

		if port_speed[idx] ~= speed then
			port_speed[idx] = speed
			mklabel(status_label[idx], speed)
		end
	end
end

function mkports()
	local grid = Gtk.Grid {}
	for idx,v in ipairs(ports) do
		local name, paths = v[1], v[2]
		local idx_label = Gtk.Label { use_markup=true, label = '<span '..idx_label_style..'><b>'..name..'</b></span> ' }
		idx_label:override_background_color(0, Gdk.RGBA.parse('black'))
		grid:add {
			left_attach = 0, top_attach = idx-1,
			idx_label
		}
		local label = Gtk.Label {
			use_markup = true,
			--hexpand    = true,
			label      = '<span '..status_label_style..'><b>?</b></span> ',
			width      = status_width,
			--width_chars = 5,
		}
		status_label[idx] = label
		grid:add{ left_attach = 1, top_attach = idx-1, label }
		local cycle    = Gtk.Button{image=Gtk.Image{stock=Gtk.STOCK_REFRESH}}
		local power    = Gtk.Button{image=Gtk.Image{stock=Gtk.STOCK_MEDIA_PLAY}}
		local shutdown = Gtk.Button{image=Gtk.Image{stock=Gtk.STOCK_MEDIA_STOP}}
		grid:add{ left_attach = 2, top_attach = idx-1, cycle}
		grid:add{ left_attach = 3, top_attach = idx-1, power}
		grid:add{ left_attach = 4, top_attach = idx-1, shutdown}
		cycle.on_button_press_event = function() cmd(paths[1],"cycle") end
		power.on_button_press_event = function() cmd(paths[1],"on") end
		shutdown.on_button_press_event = function() cmd(paths[1],"off") end
	end
	update_ports()
	return grid
end

function mk_main_window()
	local ports_lbl = Gtk.Label{
		--halign = 'FILL',
		halign = 'START',
		hexpand = true,
		use_markup = true,
		label='<span '..idx_label_style..'><b>USB Ports:</b></span>',
	}
	--ports_lbl:override_background_color(0, Gdk.RGBA.parse('black'))
	spinner = Gtk.Spinner {}
	return Gtk.Window {
		title = "USBctl",
		--default_width = 400,
		--default_height = 600,
		on_destroy = Gtk.main_quit,
		Gtk.Box {
			orientation='VERTICAL',
			Gtk.Box {
				orientation='HORIZONTAL',
				ports_lbl,
				spinner,
			},
			mkports()
		}
	}
end

local last_usb_change = nil
local timer           = nil

function refresh_timer()
	update_ports()
	local keep_timer = socket.gettime() < (last_usb_change+2)
	--print("timer",keep_timer)
	if not keep_timer then timer = nil end
	return keep_timer
end

function error_handler(err)
    print(debug.traceback("Error: " .. tostring(err)))
    Gtk.main_quit()
end

function read_line(stream)
	local line, length = stream:async_read_line()
	if type(length) ~= "number" then
		error("Error reading line: " .. tostring(length))
	end
	return line
end

function dmesg_reader(src)
	local stream = Gio.DataInputStream.new(src)
	for line in read_line, stream do
		--print(line)
		if line:find("usb ") and timer == nil then
			last_usb_change = socket.gettime()
			timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, refresh_timer);
		end
	end
end

local main_win = mk_main_window()

local dmesg = assert(Gio.Subprocess.new({"dmesg", "-t", "-w", "-k", "-P", "-W", "-Lnever"},Gio.SubprocessFlags.STDOUT_PIPE))
local dmesg_src = assert(dmesg:get_stdout_pipe()) --create_source(GLib.IOCondition.IN))
Gio.Async.start(xpcall)(dmesg_reader, error_handler, dmesg_src)

main_win:show_all()
Gtk.main()

dmesg_src:close()
dmesg:force_exit()
dmesg:wait_check()
