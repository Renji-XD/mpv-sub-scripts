local min_skip_time = 3
local start_offset = 0
local end_offset = 1
local speed_skip_speed = 2.5

local active = false
local seek_skip = false
local skipping = false
local sped_up = false
local last_sub_end, next_sub_start

function calc_next_delay()
	local initial_delay = mp.get_property_number("sub-delay")

	local initial_visibility = mp.get_property_bool("sub-visibility")
	if initial_visibility then mp.set_property_bool("sub-visibility", false) end

	mp.commandv("sub-step", "1")
	local new_delay = mp.get_property_number("sub-delay")
	mp.set_property_number("sub-delay", initial_delay)

	mp.set_property_bool("sub-visibility", initial_visibility)

	if new_delay == initial_delay then return nil
	else return -(new_delay - initial_delay) end
end

function end_seek_skip(next_sub_begin)
	mp.set_property_number("time-pos", next_sub_begin - end_offset)
	end_skip()
end

local seek_skip_timer
seek_skip_timer = mp.add_periodic_timer(128, function()
	if mp.get_property_bool("seeking") == false then
		seek_skip_timer:stop()
		local time_pos = mp.get_property_number("time-pos")
		local next_delay = calc_next_delay()
		if next_delay == nil then
			local cache_duration = mp.get_property_number("demuxer-cache-duration")
			local seek_time = cache_duration and cache_duration or 1
			mp.set_property_number("time-pos", time_pos + seek_time)
			seek_skip_timer:resume()
		else
			seek_skip_timer:kill()
			end_seek_skip(time_pos + next_delay)
			mp.set_property_bool("pause", false)
		end
	end
end)
-- make sure that the timer never fires while the script is being loaded
seek_skip_timer:kill()
seek_skip_timer.timeout = 0.05

function start_seek_skip()
	mp.unobserve_property(handle_tick)
	local next_delay = calc_next_delay()
	if next_delay ~= nil then
		end_seek_skip(mp.get_property_number("time-pos") + next_delay)
	else
		mp.set_property_bool("pause", true)
		seek_skip_timer:resume()
	end
end

local initial_speed = mp.get_property_number("speed")
local initial_video_sync = mp.get_property("video-sync")
function handle_tick(_, time_pos)
	if not sped_up and time_pos > last_sub_end + start_offset then
		if seek_skip then start_seek_skip()
		else
			initial_speed = mp.get_property_number("speed")
			initial_video_sync = mp.get_property("video-sync")
			mp.set_property("video-sync", "desync")
			mp.set_property_number("speed", speed_skip_speed)
			sped_up = true
		end
	elseif sped_up and next_sub_start == nil then
		local next_delay = calc_next_delay()
		if next_delay ~= nil then
			next_sub_start = time_pos + next_delay
		end
	elseif sped_up and time_pos > next_sub_start - end_offset then
		end_skip()
	end
end

function start_skip()
	skipping = true
	mp.observe_property("time-pos", "number", handle_tick)
end

function end_skip()
	mp.unobserve_property(handle_tick)
	skipping = false
	sped_up = false
	mp.set_property_number("speed", initial_speed)
	mp.set_property("video-sync", "audio")
	mp.set_property("video-sync", initial_video_sync)
	last_sub_end, next_sub_start = nil
end

function handle_sub_text_change(_, sub_text)
	if sub_text == "" and not skipping then
		local time_pos = mp.get_property_number("time-pos")
		local next_delay = calc_next_delay()

		if next_delay ~= nil then
			if next_delay < min_skip_time then return
			else next_sub_start = time_pos + next_delay end
		end
		last_sub_end = time_pos
		start_skip()
	elseif sub_text ~= nil and sub_text ~= "" then end_skip() end
end

mp.add_key_binding("Ctrl+n", "sub-skip-toggle", function()
	if active then
		seek_skip_timer:kill()
		mp.unobserve_property(handle_sub_text_change)
		mp.unobserve_property(handle_tick)
		last_sub_end, next_sub_start = nil
		sped_up = false
		mp.osd_message("Non-subtitle skip disabled")
	else
		mp.observe_property("sub-text", "string", handle_sub_text_change)
		mp.osd_message("Non-subtitle skip enabled")
	end
	active = not active
end)

function change_speed_skip_speed(new_value)
	speed_skip_speed = new_value
	mp.osd_message("Skip speed: " .. new_value)
end

function change_min_interval(new_value)
	min_skip_time = new_value
	mp.osd_message("Minimum interval: " .. new_value)
end

mp.add_key_binding("Ctrl+Alt+n", "sub-skip-switch-mode", function()
	seek_skip = not seek_skip
end)

mp.add_key_binding("Ctrl+Alt+[", "sub-skip-decrease-speed", function()
	change_speed_skip_speed(speed_skip_speed - 0.1)
end)

mp.add_key_binding("Ctrl+Alt+]", "sub-skip-increase-speed", function()
	change_speed_skip_speed(speed_skip_speed + 0.1)
end)

mp.add_key_binding("Ctrl+Alt+-", "sub-skip-decrease-interval", function()
	change_min_interval(min_skip_time - 0.25)
end)

mp.add_key_binding("Ctrl+Alt++", "sub-skip-increase-interval", function()
	change_min_interval(min_skip_time + 0.25)
end)
