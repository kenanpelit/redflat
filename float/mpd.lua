
-----------------------------------------------------------------------------------------------------------------------
--                                               redflat mpd widget                                               --
-----------------------------------------------------------------------------------------------------------------------
-- mpd music player widget
-----------------------------------------------------------------------------------------------------------------------

-- grab environment
-----------------------------------------------------------------------------------------------------------------------
local unpack = unpack

local awful = require("awful")
local lain = require("lain")
local helpers      = require("lain.helpers")
local async        = require("lain.asyncshell")
local escape_f     = require("awful.util").escape
local beautiful = require("beautiful")
local wibox = require("wibox")
local color = require("gears.color")
local redutil = require("redflat.util")
local progressbar = require("redflat.gauge.progressbar")
local dashcontrol = require("redflat.gauge.dashcontrol")
local svgbox = require("redflat.gauge.svgbox")
local asyncshell = require("redflat.asyncshell")
-- initialize and vars for module
-----------------------------------------------------------------------------------------------------------------------
local mpd = { box = {} }
local last = { status = "stopped" }
local command = "mpc "
local actions = { "toggle", "next", "prev" }

local args        = args or {}
local timeout     = args.timeout or 2
local password    = args.password or ""
local host        = args.host or "127.0.0.1"
local port        = args.port or "6600"
local music_dir   = args.music_dir or os.getenv("HOME") .. "/Music"
local cover_size  = args.cover_size or 100
local default_art = args.default_art or ""
local followmouse = args.followmouse or false
local echo_cmd    = args.echo_cmd or "echo"
local settings    = args.settings or function() end
local os           = { execute  = os.execute,
                       getenv   = os.getenv }

local mpdcover = helpers.scripts_dir .. "mpdcover"
local mpdh = "telnet://" .. host .. ":" .. port
local echo = echo_cmd .. " 'password " .. password .. "\nstatus\ncurrentsong\nclose'"
local music_dir   =  os.getenv("HOME") .. "/Music"
mpd_notification_preset = {
  title   = "Now playing",
  timeout = 6
}
-- generate default theme vars
-----------------------------------------------------------------------------------------------------------------------
local function default_style()
  local style = {
    geometry       = { width = 520, height = 150 },
    screen_gap     = 0,
    screen_pos     = {},
    border_gap     = { 20, 20, 20, 20 },
    elements_gap   = { 20, 0, 0, 0 },
    volume_gap     = { 0, 0, 0, 3 },
    control_gap    = { 0, 0, 18, 8 },
    buttons_margin = { 0, 0, 3, 3 },
    pause_gap      = { 12, 12 },
    timeout        = 5,
    line_height    = 26,
    bar_width      = 8, -- progress bar height
    volume_width   = 50,
    titlefont      = "sans 12",
    timefont       = "sans 12",
    artistfont     = "sans 12",
    border_width   = 2,
    icon           = {},
    color          = { border = "#575757", text = "#aaaaaa", main = "#b1222b",
               wibox = "#202020", gray = "#575757" }
  }
  return redutil.table.merge(style, redutil.check(beautiful, "float.exaile") or {})
end

-- support functions
-----------------------------------------------------------------------------------------------------------------------

-- check if mpd running
--------------------------------------------------------------------------------
local function is_mpd_running()
  return awful.util.pread("ps -e | grep mpd") ~= ""
end

local function is_mpd_playing()
  return tonumber(awful.util.pread("mpc | wc -l")) > 2
end
-- get line from output
--------------------------------------------------------------------------------
local function get_line(s)
  local line = string.match(s, "%s+(.+)")
  return line or "unknown"
end

-- initialize mpd widget
-----------------------------------------------------------------------------------------------------------------------
function mpd:init()

  -- initialize vars
  --------------------------------------------------------------------------------
  local style = default_style()
  local tr_command = command
  local show_album = false

  local current_icon = style.icon.cover
  self.info = { artist = "unknown", album = "unknown" }
  self.style = style

  -- construct layouts
  --------------------------------------------------------------------------------

  -- progressbar and icon
  self.bar = progressbar(style.progressbar)
  self.box.image = svgbox(style.icon.cover)
  self.box.image:set_color(style.color.gray)

  -- text lines
  ------------------------------------------------------------
  self.box.title = wibox.widget.textbox("title")
  self.box.artist = wibox.widget.textbox("artist")
  self.box.title:set_font(style.titlefont)
  self.box.artist:set_font(style.artistfont)

  local text_area = wibox.layout.fixed.vertical()
  text_area:add(wibox.layout.constraint(self.box.title, "exact", nil, style.line_height))
  text_area:add(wibox.layout.constraint(self.box.artist, "exact", nil, style.line_height))

  -- control line
  ------------------------------------------------------------

  -- playback buttons
  local player_buttons = wibox.layout.fixed.horizontal()
  local prev_button = svgbox(style.icon.prev_tr, nil, style.color.icon)
  player_buttons:add(prev_button)

  self.play_button = svgbox(style.icon.play, nil, style.color.icon)
  player_buttons:add(wibox.layout.margin(self.play_button, unpack(style.pause_gap)))

  local next_button = svgbox(style.icon.next_tr, nil, style.color.icon)
  player_buttons:add(next_button)

  -- time indicator
  self.box.time = wibox.widget.textbox("0:00")
  self.box.time:set_font(style.timefont)

  -- volume
  self.volume = dashcontrol(style.dashcontrol)
  local volumespace = wibox.layout.margin(self.volume, unpack(style.volume_gap))
  local volume_area = wibox.layout.constraint(volumespace, "exact", style.volume_width, nil)

  -- full line
  local control_align = wibox.layout.align.horizontal()
  control_align:set_middle(wibox.layout.margin(player_buttons, unpack(style.buttons_margin)))
  control_align:set_right(self.box.time)
  control_align:set_left(volume_area)

  -- bring it all together
  ------------------------------------------------------------
  local align_vertical = wibox.layout.align.vertical()
  align_vertical:set_top(text_area)
  align_vertical:set_middle(wibox.layout.margin(control_align, unpack(style.control_gap)))
  align_vertical:set_bottom(wibox.layout.constraint(self.bar, "exact", nil, style.bar_width))
  local area = wibox.layout.fixed.horizontal()
  area:add(self.box.image)
  area:add(wibox.layout.margin(align_vertical, unpack(style.elements_gap)))

  -- buttons
  ------------------------------------------------------------

  -- playback controll
  self.play_button:buttons(awful.util.table.join(awful.button({}, 1, function() awful.util.spawn("mpc toggle") end)))
  next_button:buttons(awful.util.table.join(awful.button({}, 1, function() awful.util.spawn("mpc next") end)))
  prev_button:buttons(awful.util.table.join(awful.button({}, 1, function() awful.util.spawn("mpc prev") end)))

  -- volume
  self.volume:buttons(awful.util.table.join(
                        awful.button({}, 4, function() awful.util.spawn("mpc volume +5") end),
                        awful.button({}, 5, function()awful.util.spawn("mpc volume -5") end)
  ))

  -- switch between artist and album info on mouse click
  self.box.artist:buttons(awful.util.table.join(
    awful.button({}, 1,
      function()
        show_album = not show_album
      end
    )
  ))

  -- create floating wibox for mpd widget
  --------------------------------------------------------------------------------
  self.wibox = wibox({
    ontop        = true,
    bg           = style.color.wibox,
    border_width = style.border_width,
    border_color = style.color.border
  })

  self.wibox:set_widget(wibox.layout.margin(area, unpack(style.border_gap)))
  self.wibox:geometry(style.geometry)

  -- update info functions
  --------------------------------------------------------------------------------

  -- function to set play button state
  ------------------------------------------------------------
  self.set_play_button = function(state)
    self.play_button:set_image(style.icon[state])
  end

  -- function to set info for artist/album line
  ------------------------------------------------------------
  self.update_artist = function()
    self.update()
  end

  -- set defs
  ------------------------------------------------------------
  self.clear_info = function(is_att)
    self.box.image:set_image(style.icon.cover)
    self.box.image:set_color(is_att and style.color.main or style.color.gray)

    self.box.time:set_text("0:00")
    self.bar:set_value(0)
    --self.box.title:set_text("stopped")
    --self.info = { artist = "", album = "" }
    --self.update_artist()
  end

  -- main update function
  ------------------------------------------------------------
  function self:update()

        async.request(echo .. " | curl --connect-timeout 1 -fsm 3 " .. mpdh, function (f)
            mpd_now = {
                state   = "N/A",
                file    = "N/A",
                name    = "N/A",
                artist  = "N/A",
                title   = "N/A",
                album   = "N/A",
                date    = "N/A",
                time    = "N/A",
                elapsed = "N/A"
            }

            for line in string.gmatch(f, "[^\n]+") do
                for k, v in string.gmatch(line, "([%w]+):[%s](.*)$") do
                    if     k == "state"   then mpd_now.state   = v
                    elseif k == "file"    then mpd_now.file    = v
                    elseif k == "Name"    then mpd_now.name    = escape_f(v)
                    elseif k == "Artist"  then mpd_now.artist  = escape_f(v)
                    elseif k == "Title"   then mpd_now.title   = escape_f(v)
                    elseif k == "Album"   then mpd_now.album   = escape_f(v)
                    elseif k == "Date"    then mpd_now.date    = escape_f(v)
                    elseif k == "Time"    then mpd_now.time    = v
                    elseif k == "elapsed" then mpd_now.elapsed = string.match(v, "%d+")
                    end
                end
            end

      if show_album then
        self.box.artist:set_text(mpd_now.album)
      else
        self.box.artist:set_text(mpd_now.artist)
      end
      local min = math.floor((mpd_now.elapsed / 60 )%60)
      local sec = math.floor(mpd_now.elapsed % 60)
      self.box.title:set_text(mpd_now.title)
      self.box.time:set_text(string.format("%02d:%02d",min,sec))
      self.bar:set_value(mpd_now.elapsed / mpd_now.time)
      self.volume:set_value(tonumber(awful.util.pread("mpc |grep volume:| sed \'s/volume:\\s*\\([0-9]*\\)%.*/\\1/g\'"))/100)
        end)
  end
  -- set update timer
  --------------------------------------------------------------------------------
  self.updatetimer = timer({ timeout = 1})
  self.updatetimer:connect_signal("timeout", function() self:update() end)

end

-- player playback control
-----------------------------------------------------------------------------------------------------------------------
function mpd:action(args)
  if not awful.util.table.hasitem(actions, args) then return end
  if not mpd.wibox then mpd:init() end

  if is_mpd_running() then
    awful.util.spawn_with_shell(command .. args)
    self:update()
  end
end


-- hide mpd widget
-----------------------------------------------------------------------------------------------------------------------
function mpd:hide()
  self.wibox.visible = false
  self.updatetimer:stop()
end

-- show mpd widget
-----------------------------------------------------------------------------------------------------------------------
function mpd:show()
  if not self.wibox then self:init() end

  if not self.wibox.visible then
    self:update()
    if self.style.screen_pos[mouse.screen] then self.wibox:geometry(self.style.screen_pos[mouse.screen]) end
    redutil.placement.no_offscreen(self.wibox, self.style.screen_gap, screen[mouse.screen].workarea)
    self.wibox.visible = true
    self.updatetimer:start()
  else
    self:hide()
  end
end



-- end
-----------------------------------------------------------------------------------------------------------------------
return mpd
