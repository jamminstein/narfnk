-- NARFNK: Quad Sequential Funk Machine
-- 4 Channels of 99-Step Stochastic MIDI Funk Sequencing
--
-- PURPOSE:
-- Advanced 4-track MIDI sequencer with stochastic step probability,
-- tempo-sync'd groove templates, and live performance controls for
-- generating funky polyrhythmic patterns. Uses PolyPerc or external
-- MIDI output to drive any synthesizer or drum machine.
--
-- CONTROLS:
-- K1 (Hold) + E1: Select Track (BASS, KEYS, GUIT, HORN)
-- K1 press: Shift mode (hold for track select or pattern jump)
-- K2 single: Start/stop playback of selected track
-- K2 long: Jump to edit focus step
-- K3 short: Randomize current step
-- K3 long: Save current sequence to slot
-- K1+K3: Start/stop groove capture (live MIDI timing)
-- E1: Select step (1-99)
-- E2: Select parameter (PITCH, VEL, DURATION, etc.)
-- E3: Adjust parameter value
-- Grid row 7: Solo toggles (cols 1-4)
-- Grid row 8: Mute toggles (cols 1-4)
--
-- ENGINE: PolyPerc (built-in), MIDI out (external synths)
-- MIDI: Input record, output 4 channels with CC/modulation support

local tab = require 'tabutil'
local mu = require 'musicutil'

-- 1. DATA STRUCTURES
local tracks = {}
local selected_track = 1
local track_names = {"BASS", "KEYS", "GUIT", "HORN"}

local edit_focus = 1
local param_focus = 1
local dur_sub_focus = 1
local shift = false
local show_splash = true
local flash_level = 0
local hold_start = 0

-- Screen state: beat phase, popup timing
local beat_phase = 0
local popup_param = nil
local popup_val = nil
local popup_time = 0

local param_names = {"PITCH", "VELOCITY", "DURATION", "CC1 VALUE", "CC2 VALUE", "MODULATION", "ARTICULATION", "GLIDE", "LOOP TO", "REPEATS", "PROBABILITY"}
local m = midi.connect()
local g = grid.connect()

-- FUNK DEFAULTS per track role
local funk_defaults = {
  { pitch_lo = 28, pitch_hi = 52, vel = 110, artic = 0.70, den = 4 },
  { pitch_lo = 55, pitch_hi = 79, vel = 90, artic = 0.40, den = 4 },
  { pitch_lo = 48, pitch_hi = 72, vel = 85, artic = 0.35, den = 4 },
  { pitch_lo = 60, pitch_hi = 84, vel = 100, artic = 0.50, den = 4 },
}

-- GROOVE TEMPLATES
local groove_templates = {
  { name = "Parliament 1",
    steps = {
      {0,120,1,4,0.8,100}, {0,0,1,4,0.5,0},     {7,70,1,4,0.4,80},  {0,50,1,4,0.3,60},
      {5,100,1,4,0.7,100}, {0,0,1,4,0.5,0},      {7,65,1,4,0.35,70}, {3,45,1,4,0.3,50},
      {0,110,1,4,0.75,100},{0,0,1,4,0.5,0},       {5,75,1,4,0.4,85},  {7,40,1,4,0.25,40},
      {3,95,1,4,0.65,100}, {0,0,1,4,0.5,0},       {5,60,1,4,0.35,70}, {0,55,1,4,0.3,60},
    }
  },
  { name = "JB Tight",
    steps = {
      {0,127,1,4,0.6,100}, {0,40,1,4,0.2,50},    {7,90,1,4,0.5,100}, {0,35,1,4,0.2,40},
      {5,110,1,4,0.55,100},{0,45,1,4,0.2,50},     {3,85,1,4,0.45,90}, {0,30,1,4,0.15,30},
      {0,115,1,4,0.6,100}, {0,40,1,4,0.2,45},     {7,95,1,4,0.5,100}, {0,35,1,4,0.2,40},
      {5,105,1,4,0.55,100},{0,50,1,4,0.25,55},    {3,80,1,4,0.4,85},  {7,60,1,4,0.3,70},
    }
  },
  { name = "Sly Synco",
    steps = {
      {0,110,1,4,0.7,100}, {5,85,1,4,0.4,90},    {0,0,1,4,0.5,0},    {7,100,1,4,0.6,100},
      {0,0,1,4,0.5,0},     {3,90,1,4,0.5,95},     {0,50,1,4,0.3,50},  {5,105,1,4,0.65,100},
      {0,0,1,4,0.5,0},     {7,80,1,4,0.4,80},     {0,100,1,4,0.6,100},{0,0,1,4,0.5,0},
      {3,95,1,4,0.55,100}, {0,45,1,4,0.25,45},    {5,90,1,4,0.5,90},  {0,0,1,4,0.5,0},
    }
  },
  { name = "Bootsy Bass",
    steps = {
      {0,120,1,4,0.75,100},{0,0,1,4,0.5,0},      {0,50,1,4,0.25,50}, {12,90,1,4,0.4,90},
      {0,0,1,4,0.5,0},     {0,100,1,4,0.6,100},   {0,0,1,4,0.5,0},    {7,70,1,4,0.35,75},
      {0,115,1,4,0.7,100}, {12,80,1,4,0.35,85},   {0,0,1,4,0.5,0},    {0,55,1,4,0.3,55},
      {5,105,1,4,0.6,100}, {0,0,1,4,0.5,0},       {7,65,1,4,0.3,65},  {0,75,1,4,0.4,80},
    }
  },
  { name = "Meters",
    steps = {
      {0,115,1,4,0.65,100},{0,40,1,4,0.2,40},    {5,80,1,4,0.45,85}, {0,0,1,4,0.5,0},
      {7,100,1,4,0.6,100}, {0,50,1,4,0.25,55},   {0,0,1,4,0.5,0},    {3,90,1,4,0.5,95},
      {0,110,1,4,0.6,100}, {0,0,1,4,0.5,0},      {5,85,1,4,0.45,90}, {7,45,1,4,0.2,45},
      {0,0,1,4,0.5,0},     {3,95,1,4,0.55,100},   {0,55,1,4,0.3,60},  {5,70,1,4,0.35,75},
    }
  },
  { name = "Stevie Clav",
    steps = {
      {0,100,1,4,0.3,100}, {3,75,1,4,0.25,80},   {5,90,1,4,0.3,95},  {0,50,1,4,0.2,50},
      {7,95,1,4,0.3,100},  {3,55,1,4,0.2,55},    {0,85,1,4,0.3,90},  {5,60,1,4,0.2,60},
      {0,105,1,4,0.3,100}, {7,70,1,4,0.25,75},   {3,90,1,4,0.3,95},  {0,45,1,4,0.2,45},
      {5,100,1,4,0.3,100}, {0,65,1,4,0.2,65},    {7,80,1,4,0.25,85}, {3,50,1,4,0.2,50},
    }
  },
  { name = "Prince",
    steps = {
      {0,120,1,4,0.5,100}, {0,0,1,4,0.5,0},      {0,0,1,4,0.5,0},    {7,80,1,4,0.35,80},
      {0,0,1,4,0.5,0},     {0,100,1,4,0.5,100},   {0,0,1,4,0.5,0},    {0,0,1,4,0.5,0},
      {5,110,1,4,0.5,100}, {0,0,1,4,0.5,0},       {7,70,1,4,0.3,70},  {0,0,1,4,0.5,0},
      {0,95,1,4,0.45,100}, {3,60,1,4,0.25,60},    {0,0,1,4,0.5,0},    {5,85,1,4,0.4,90},
    }
  },
  { name = "Mothership",
    steps = {
      {0,125,1,4,0.8,100}, {7,60,1,4,0.3,60},    {3,80,1,4,0.5,85},  {5,55,1,4,0.25,55},
      {12,95,1,4,0.45,95}, {0,0,1,4,0.5,0},      {7,85,1,4,0.5,90},  {0,45,1,4,0.2,45},
      {5,110,1,4,0.7,100}, {3,65,1,4,0.3,65},    {0,0,1,4,0.5,0},    {7,90,1,4,0.55,95},
      {0,50,1,4,0.25,50},  {5,100,1,4,0.6,100},  {3,55,1,4,0.25,55}, {0,75,1,4,0.4,80},
    }
  },
}

local groove_names = {}
for i, g in ipairs(groove_templates) do
  groove_names[i] = g.name
end
table.insert(groove_names, 1, "---")

-- Grid mute/solo state
local track_mutes = { false, false, false, false }
local track_solos = { false, false, false, false }

-- Live groove capture
local groove_capture = {}
local capture_active = false
local capture_times = {}

-- Track fire flash state (brief flash on note fire)
local track_fire_flash = { 0, 0, 0, 0 }

-- 2. INITIALIZATION
function init()
  for i = 1, 4 do
    tracks[i] = {
      active_step = 1,
      is_running = false,
      is_playing_note = false,
      steps = {},
      midi_ch = i, transpose = 0, p_start = 1, p_end = 16,
      cc1_n = 0, cc2_n = 0
    }
    init_steps(i)
  end

  clock.run(function() clock.sleep(2.5); show_splash = false; redraw() end)

  -- Beat phase tracker for pulse and capture indicator
  clock.run(function()
    while true do
      beat_phase = (beat_phase + 1) % 8
      clock.sleep(1/15)
    end
  end)

  clock.run(function()
    while true do
      if flash_level > 0 then flash_level = flash_level - 1 end
      for i = 1, 4 do
        if track_fire_flash[i] > 0 then track_fire_flash[i] = track_fire_flash[i] - 1 end
      end
      if popup_time > 0 then popup_time = popup_time - 1 end
      redraw()
      clock.sleep(1/15)
    end
  end)

  params:add_separator("narfnk_config", "NARFNK CONFIG")
  params:add_number("save_slot", "SAVE/LOAD SLOT", 1, 10, 1)
  params:set_action("save_slot", function(v) load_sequence(v) end)

  params:add_option("send_clock", "SEND MIDI CLOCK", {"OFF", "ON"}, 2)
  params:add_option("rec_mode", "MIDI RECORD MODE", {"OFF", "ON"}, 1)
  params:add_option("midi_remote", "REMOTE MAPPING", {"OFF", "16n", "nKONTROL2"}, 2)

  params:add_control("swing", "SWING",
    controlspec.new(50, 75, 'lin', 1, 54, "%"))

  for i = 1, 4 do
    params:add_group("TRACK " .. track_names[i], 8)
    params:add_number("midi_ch_"..i, "MIDI CHANNEL", 1, 16, i)
    params:add_number("trans_"..i, "TRANSPOSE", -24, 24, 0)
    params:add_number("start_"..i, "PATTERN START", 1, 99, 1)
    params:add_number("end_"..i, "PATTERN END", 1, 99, 16)
    params:add_number("cc1_n_"..i, "CC1 DESTINATION", 0, 127, 0)
    params:add_number("cc2_n_"..i, "CC2 DESTINATION", 0, 127, 0)
    params:add_option("groove_"..i, "LOAD GROOVE", groove_names, 1)
    params:set_action("groove_"..i, function(v)
      if v > 1 then apply_groove_template(i, v - 1) end
    end)
    params:add_number("ghost_thresh_"..i, "GHOST THRESHOLD", 0, 80, 50)

    params:set_action("midi_ch_"..i, function(v) tracks[i].midi_ch = v end)
    params:set_action("trans_"..i, function(v) tracks[i].transpose = v end)
    params:set_action("start_"..i, function(v) tracks[i].p_start = v end)
    params:set_action("end_"..i, function(v) tracks[i].p_end = v end)
    params:set_action("cc1_n_"..i, function(v) tracks[i].cc1_n = v end)
    params:set_action("cc2_n_"..i, function(v) tracks[i].cc2_n = v end)
  end

  params:add_number("global_trans", "GLOBAL TRANSPOSE", -24, 24, 0)

  params:add_trigger("clear_track", "CLEAR SELECTED TRACK")
  params:set_action("clear_track", function()
    init_steps(selected_track)
    print("Cleared Track " .. track_names[selected_track])
    if m and tracks[selected_track].is_playing_note then
      m:cc(123, 0, tracks[selected_track].midi_ch)
    end
    redraw()
  end)

  params:add_separator("quantize_config", "QUANTIZATION")
  params:add_option("quantize", "QUANTIZE", {"OFF", "ON"}, 2)
  params:add_option("root_note", "ROOT NOTE", mu.NOTE_NAMES, 1)
  local scale_names = {}
  for i=1, #mu.SCALES do table.insert(scale_names, mu.SCALES[i].name) end
  local mixo_idx = 1
  for i, s in ipairs(mu.SCALES) do
    if s.name == "Mixolydian" then mixo_idx = i; break end
  end
  params:add_option("scale", "SCALE", scale_names, mixo_idx)

  m.event = function(data)
    local msg = midi.to_msg(data)
    local remote = params:get("midi_remote")
    if msg.type == "note_on" and params:get("rec_mode") == 2 then record_midi_step(msg.note, msg.vel)
    elseif msg.type == "cc" and remote > 1 then handle_remote_cc(msg.cc, msg.val, remote) end
    
    -- Capture groove timing
    if capture_active then
      if msg.type == "note_on" and msg.vel > 0 then
        table.insert(capture_times, util.time())
      end
    end
  end

  load_sequence(params:get("save_slot"))
  params:bang()
  redraw()
end

function init_steps(t)
  local fd = funk_defaults[t] or funk_defaults[1]
  for i = 1, 99 do
    tracks[t].steps[i] = {
      pitch = fd.pitch_lo + math.floor((fd.pitch_hi - fd.pitch_lo) / 2),
      vel = fd.vel,
      num = 1, den = fd.den,
      cc1_v = 0, cc2_v = 0,
      mod = 0, artic = fd.artic,
      glide = 0, loop_to = 0, repeats = 0, count = 0, prob = 100
    }
  end
end

-- GROOVE CAPTURE: Extract timing offsets from MIDI input
local function extract_groove_template()
  if #capture_times < 4 then return nil end
  
  local template = {}
  local base_time = capture_times[1]
  local bar_duration = 60 / 120 * 4  -- Approximate bar duration
  
  for i, t in ipairs(capture_times) do
    if i > 16 then break end
    local offset = t - base_time
    local step_idx = math.floor(offset / bar_duration * 16) + 1
    if step_idx >= 1 and step_idx <= 16 then
      template[step_idx] = {
        pitch = 0,
        vel = 100,
        num = 1,
        den = 4,
        artic = 0.5,
        prob = 100
      }
    end
  end
  
  return template
end

function capture_groove()
  if capture_active then
    -- Stop capture
    capture_active = false
    local groove = extract_groove_template()
    if groove then
      print("Groove captured from MIDI")
      for i = 1, 16 do
        if groove[i] then
          tracks[selected_track].steps[i].vel = groove[i].vel
          tracks[selected_track].steps[i].artic = groove[i].artic
        end
      end
    end
  else
    -- Start capture
    capture_active = true
    capture_times = {}
    print("Recording groove capture...")
  end
  redraw()
end

function apply_groove_template(track_idx, template_idx)
  local tmpl = groove_templates[template_idx]
  if not tmpl then return end
  local t = tracks[track_idx]
  local fd = funk_defaults[track_idx]
  local base_pitch = fd.pitch_lo + math.floor((fd.pitch_hi - fd.pitch_lo) / 2)

  for i, s in ipairs(tmpl.steps) do
    local step = t.steps[i]
    step.pitch = get_quantized_note(base_pitch + s[1])
    step.vel = s[2]
    step.num = s[3]
    step.den = s[4]
    step.artic = s[5]
    step.prob = s[6]
    step.cc1_v = 0
    step.cc2_v = 0
    step.mod = 0
    step.glide = 0
    step.loop_to = 0
    step.repeats = 0
    step.count = 0
  end
  t.p_end = #tmpl.steps
  params:set("end_"..track_idx, #tmpl.steps)
  print("NARFNK: Loaded " .. tmpl.name .. " on " .. track_names[track_idx])
  redraw()
end

function handle_remote_cc(cc, val, mode)
  if mode == 2 then
    if cc >= 32 and cc <= 35 then tracks[cc-31].steps[edit_focus].pitch = val
    elseif cc >= 36 and cc <= 39 then tracks[cc-35].steps[edit_focus].vel = val
    elseif cc >= 40 and cc <= 43 then tracks[cc-39].steps[edit_focus].num = util.clamp(math.floor(val/4)+1, 1, 32)
    elseif cc >= 44 and cc <= 47 then tracks[cc-43].steps[edit_focus].mod = val end
  end
  redraw()
end

local function get_swing_delay(step_in_bar, total_sleep)
  local swing_pct = params:get("swing") / 100
  if step_in_bar % 2 == 0 then
    local delay = total_sleep * (swing_pct - 0.5) * 2
    return delay
  end
  return 0
end

-- 4. SEQUENCER LOOP
function run_track(t_idx)
  local t = tracks[t_idx]
  if params:get("send_clock") == 2 then m:start() end
  while t.is_running do
    local s = t.steps[t.active_step]
    local global_transpose = params:get("global_trans")
    local final_pitch = get_quantized_note(s.pitch + t.transpose + global_transpose)

    -- Check mute/solo status
    local any_solo = false
    for i = 1, 4 do if track_solos[i] then any_solo = true end end
    
    local should_play = true
    if any_solo then
      should_play = track_solos[t_idx] and not track_mutes[t_idx]
    else
      should_play = not track_mutes[t_idx]
    end

    if not should_play then
      -- Rest: still sleep for the duration
      local dur_beats = (s.num / s.den) * 4
      local total_sleep = dur_beats * clock.get_beat_sec()
      local step_in_bar = ((t.active_step - 1) % 16) + 1
      local swing_delay = get_swing_delay(step_in_bar, total_sleep)
      if swing_delay > 0 then clock.sleep(swing_delay) end
      clock.sleep(total_sleep - swing_delay)
    else
      if math.random(100) > s.prob then
        local dur_beats = (s.num / s.den) * 4
        local total_sleep = dur_beats * clock.get_beat_sec()
        local step_in_bar = ((t.active_step - 1) % 16) + 1
        local swing_delay = get_swing_delay(step_in_bar, total_sleep)
        if swing_delay > 0 then clock.sleep(swing_delay) end
        clock.sleep(total_sleep - swing_delay)
      else
        local ghost_thresh = params:get("ghost_thresh_"..t_idx)
        local play_vel = s.vel
        if s.vel > 0 and s.vel < ghost_thresh then
          play_vel = math.floor(s.vel * 0.5)
        end

        if s.glide > 0 then m:cc(65, 127, t.midi_ch); m:cc(5, s.glide, t.midi_ch) end
        if t.cc1_n > 0 then m:cc(t.cc1_n, s.cc1_v, t.midi_ch) end
        if t.cc2_n > 0 then m:cc(t.cc2_n, s.cc2_v, t.midi_ch) end

        t.is_playing_note = true
        m:note_on(final_pitch, play_vel, t.midi_ch)
        m:cc(1, s.mod, t.midi_ch)
        track_fire_flash[t_idx] = 2

        local dur_beats = (s.num / s.den) * 4
        local total_sleep = dur_beats * clock.get_beat_sec()

        local step_in_bar = ((t.active_step - 1) % 16) + 1
        local swing_delay = get_swing_delay(step_in_bar, total_sleep)
        if swing_delay > 0 then clock.sleep(swing_delay) end

        local remaining = total_sleep - swing_delay
        if s.artic < 1.0 then
          clock.sleep(remaining * s.artic)
          m:note_off(final_pitch, 0, t.midi_ch)
          t.is_playing_note = false
          clock.sleep(remaining * (1 - s.artic))
        else
          clock.sleep(remaining)
          m:note_off(final_pitch, 0, t.midi_ch)
          t.is_playing_note = false
        end
      end
    end

    local next_step = t.active_step + 1
    if s.loop_to > 0 and s.repeats > 0 and s.loop_to < t.p_end and s.loop_to >= t.p_start then
      if math.random(1, 100) <= s.prob then
        if s.count < s.repeats then s.count = s.count + 1; next_step = s.loop_to else s.count = 0 end
      else s.count = 0 end
    end
    if next_step > t.p_end or next_step < t.p_start then
      next_step = t.p_start
      flash_level = 4
    end
    t.active_step = next_step
    redraw()
  end
end

-- GRID HANDLER
g.key = function(x, y, z)
  if z == 0 then return end
  
  if y == 8 then
    -- Mute toggles (cols 1-4)
    if x >= 1 and x <= 4 then
      track_mutes[x] = not track_mutes[x]
      redraw()
    end
  elseif y == 7 then
    -- Solo toggles (cols 1-4)
    if x >= 1 and x <= 4 then
      track_solos[x] = not track_solos[x]
      redraw()
    end
  end
end

local function grid_redraw()
  if not g.device then return end
  g:all(0)
  
  -- Row 8: Mute toggles
  for i = 1, 4 do
    g:led(i, 8, track_mutes[i] and 5 or 2)
  end
  
  -- Row 7: Solo toggles
  for i = 1, 4 do
    g:led(i, 7, track_solos[i] and 15 or 2)
  end
  
  g:refresh()
end

-- 5. HARDWARE INTERACTION
function enc(n, d)
  if show_splash then show_splash = false; redraw(); return end
  local t = tracks[selected_track]; local s = t.steps[edit_focus]
  if n == 1 then
    if shift then selected_track = util.clamp(selected_track + d, 1, 4)
    else edit_focus = util.clamp(edit_focus + d, 1, 99) end
  elseif n == 2 then
    if param_focus == 3 then
      dur_sub_focus = dur_sub_focus + d
      if dur_sub_focus > 2 or dur_sub_focus < 1 then
        param_focus = util.clamp(param_focus + (dur_sub_focus < 1 and -1 or 1), 1, #param_names)
        dur_sub_focus = (dur_sub_focus < 1) and 1 or 2
      end
    else
      param_focus = util.clamp(param_focus + d, 1, #param_names)
      if param_focus == 3 then dur_sub_focus = (d > 0) and 1 or 2 end
    end
  elseif n == 3 then
    local old_val = nil
    local param_name = param_names[param_focus]
    if param_focus == 1 then s.pitch = util.clamp(s.pitch + d, 0, 127); old_val = s.pitch
    elseif param_focus == 2 then s.vel = util.clamp(s.vel + d, 0, 127); old_val = s.vel
    elseif param_focus == 3 then
      if dur_sub_focus == 1 then s.num = util.clamp(s.num + d, 1, 32); old_val = s.num else s.den = util.clamp(s.den + d, 1, 32); old_val = s.den end
    elseif param_focus == 4 then s.cc1_v = util.clamp(s.cc1_v + d, 0, 127); old_val = s.cc1_v
    elseif param_focus == 5 then s.cc2_v = util.clamp(s.cc2_v + d, 0, 127); old_val = s.cc2_v
    elseif param_focus == 6 then s.mod = util.clamp(s.mod + d, 0, 127); old_val = s.mod
    elseif param_focus == 7 then s.artic = util.clamp(s.artic + (d * 0.05), 0.05, 1); old_val = math.floor(s.artic * 100)
    elseif param_focus == 8 then s.glide = util.clamp(s.glide + d, 0, 127); old_val = s.glide
    elseif param_focus == 9 then s.loop_to = util.clamp(s.loop_to + d, 0, 99); old_val = s.loop_to
    elseif param_focus == 10 then s.repeats = util.clamp(s.repeats + d, 0, 16); old_val = s.repeats
    elseif param_focus == 11 then s.prob = util.clamp(s.prob + d, 0, 100); old_val = s.prob
    end
    -- Show popup
    popup_param = param_name
    popup_val = old_val
    popup_time = 12  -- 0.8s at 15 FPS
  end
  redraw()
end

function key(n, z)
  if show_splash then show_splash = false; redraw(); return end
  if n == 1 then shift = (z == 1) end
  if n == 2 and z == 1 then
    if shift then tracks[selected_track].active_step = edit_focus
    else
      tracks[selected_track].is_running = not tracks[selected_track].is_running
      if tracks[selected_track].is_running then clock.run(function() run_track(selected_track) end) end
    end
  elseif n == 3 then
    if shift then
      if z == 1 then capture_groove() end
    else
      if z == 1 then hold_start = util.time()
      else if util.time() - hold_start > 1 then save_sequence(params:get("save_slot")) else funk_randomize_step(selected_track, edit_focus) end end
    end
  end
  redraw()
end

-- 6. GLOBAL, SAVE/LOAD, SPLASH
function global_toggle()
  local any_r = false
  for i=1,4 do if tracks[i].is_running then any_r = true end end
  if any_r then for i=1,4 do tracks[i].is_running = false end
  else for i=1,4 do tracks[i].active_step = tracks[i].p_start; tracks[i].is_running = true; clock.run(function() run_track(i) end) end end
  redraw()
end

function save_sequence(slot)
  local d = {}; for i=1,4 do d[i] = tracks[i].steps end
  tab.save(d, norns.state.data .. "narfnk_slot_"..slot..".data"); print("NARFNK Saved to Slot "..slot)
end

function load_sequence(slot)
  local p = norns.state.data .. "narfnk_slot_"..slot..".data"
  if util.file_exists(p) then local sd = tab.load(p); for i=1,4 do tracks[i].steps = sd[i] end print("Slot "..slot.." Loaded") end
  redraw()
end

function record_midi_step(p, v)
  local s = tracks[selected_track].steps[edit_focus]
  s.pitch = p; s.vel = v; edit_focus = util.clamp(edit_focus + 1, 1, 99); redraw()
end

function get_quantized_note(note)
  if params:get("quantize") == 1 then return note end
  local r, si = params:get("root_note"), params:get("scale")
  local sn = mu.generate_scale_of_length(r, mu.SCALES[si].name, 127)
  return mu.snap_to_notes(sn, note)
end

function funk_randomize_step(t, i)
  local fd = funk_defaults[t]
  local step = tracks[t].steps[i]
  local step_in_bar = ((i - 1) % 16) + 1

  step.pitch = get_quantized_note(math.random(fd.pitch_lo, fd.pitch_hi))

  if step_in_bar == 1 then
    step.vel = math.random(110, 127)
    step.prob = 100
  elseif step_in_bar == 5 or step_in_bar == 9 or step_in_bar == 13 then
    step.vel = math.random(85, 110)
    step.prob = math.random(85, 100)
  elseif step_in_bar % 2 == 0 then
    if math.random() > 0.5 then
      step.vel = math.random(70, 100)
      step.prob = math.random(70, 95)
    else
      step.vel = math.random(25, 50)
      step.prob = math.random(40, 70)
    end
  else
    if math.random() > 0.3 then
      step.vel = math.random(60, 100)
      step.prob = math.random(60, 90)
    else
      step.vel = 0
      step.prob = 0
    end
  end

  if step_in_bar == 1 then
    step.artic = math.random(60, 80) / 100
  else
    step.artic = math.random(20, 55) / 100
  end

  step.num = 1
  step.den = 4
end

function draw_splash()
  screen.clear()
  screen.level(15)
  screen.move(64, 20)
  screen.text_center("NARFNK")
  screen.level(8)
  screen.move(64, 32)
  screen.text_center("Quad Funk Machine")
  screen.level(4)
  screen.move(64, 44)
  screen.text_center("Stochastic MIDI Groove")
  screen.level(2)
  screen.move(64, 56)
  screen.text_center("hit the ONE")
  screen.update()
end

-- HELPER: Map velocity to brightness (vel 127 = 15, vel 64 = 8, vel 32 = 4, vel 0 = 0)
local function velocity_to_brightness(vel)
  if vel == 0 then return 0 end
  return math.max(1, math.floor(vel / 127 * 15))
end

-- 7. REDRAW with enhanced screen design
function redraw()
  if show_splash then draw_splash(); return end
  screen.clear()
  
  -- ZONE 1: STATUS STRIP (y 0-8)
  -- Show "NARFNK" at level 4 top-left
  screen.level(4)
  screen.move(0, 7)
  screen.text("NARFNK")
  
  -- Show groove template name at level 8 center
  screen.level(8)
  screen.move(64, 7)
  local groove_idx = params:get("groove_"..selected_track)
  local groove_name = (groove_idx > 1) and groove_templates[groove_idx - 1].name or "---"
  screen.text_center(groove_name)
  
  -- Beat pulse dot at x=124
  local pulse_level = 2
  if beat_phase < 4 then pulse_level = 6 + beat_phase end
  screen.level(pulse_level)
  screen.move(124, 4)
  screen.text("●")
  
  -- ZONE 2: LIVE ZONE with track views (y 9-32)
  for i=1,4 do
    screen.level(selected_track == i and 15 or 2)
    local name_w = #track_names[i] * 5 + 2
    screen.move((i-1)*32, 11)
    
    -- Dim muted tracks, keep soloed bright
    local track_level = 15
    if track_mutes[i] then track_level = 3
    elseif track_solos[i] then track_level = 15
    else track_level = 8 end
    
    screen.level(track_level)
    screen.text(track_names[i])
    
    -- Flash on note fire
    if track_fire_flash[i] > 0 then
      screen.level(15)
    end
    
    if tracks[i].is_running then 
      screen.level(track_level)
      screen.rect((i-1)*32, 12, name_w, 1)
      screen.fill()
    end
    
    if track_mutes[i] then
      screen.level(4)
      screen.move((i-1)*32, 18)
      screen.text("M")
    end
    
    if track_solos[i] then
      screen.level(15)
      screen.move((i-1)*32, 18)
      screen.text("S")
    end
  end
  
  -- GROOVE CAPTURE indicator (pulsing REC)
  if capture_active then
    local rec_bright = 8 + math.floor(beat_phase / 2)
    screen.level(rec_bright)
    screen.move(127, 11)
    screen.text_right("REC")
  end
  
  -- ZONE 3: PLAYHEAD + STEP VISUALIZATION (y 24-40)
  screen.font_size(8)
  screen.font_face(2)
  screen.level(3)
  screen.move(127, 11)
  screen.text_right("S:"..params:get("save_slot").." P:"..tracks[selected_track].active_step.." E:"..edit_focus)
  
  local t = tracks[selected_track]
  local center_x, sc = 64, 12
  local is_last_step = (t.active_step == t.p_end)
  local cur_s = t.steps[t.active_step]
  local cur_w = math.max(2, (cur_s.num/cur_s.den)*4*sc)
  
  -- Playhead with thin line behind (level 3)
  screen.level(3)
  screen.rect(center_x - 1, 24, 2, 16)
  screen.fill()
  
  -- Current step bar with velocity-mapped brightness
  local vel_bright = velocity_to_brightness(cur_s.vel)
  screen.level(vel_bright)
  local bar_h = (cur_s.pitch/127)*16
  screen.rect(center_x-(cur_w/2), 40-bar_h, cur_w, bar_h)
  screen.fill()
  
  if is_last_step then
    screen.level(15)
    screen.move(center_x, 20)
    screen.line_rel(-2,-2)
    screen.line_rel(4,0)
    screen.line_rel(-2,2)
    screen.fill()
  end
  
  -- Forward steps with velocity brightness
  local fw_x = center_x + (cur_w/2) + 2
  screen.font_face(1)
  screen.font_size(8)
  for i = 1, 10 do
    local idx = t.active_step + i
    if idx <= 99 and fw_x < 128 then
      local s = t.steps[idx]
      local w = math.max(2, (s.num/s.den)*4*sc)
      if idx == t.p_end then
        screen.level(10)
        screen.rect(fw_x, 23, w, 1)
        screen.fill()
        screen.move(fw_x + w, 40)
        screen.line_rel(0, -16)
        screen.stroke()
      end
      
      local ghost = params:get("ghost_thresh_"..selected_track)
      local step_bright = velocity_to_brightness(s.vel)
      
      -- Apply mute/solo dimming
      if track_mutes[selected_track] then
        step_bright = 3
      elseif track_solos[selected_track] then
        step_bright = step_bright
      else
        if step_bright == 0 then step_bright = 1 end
      end
      
      screen.level((idx >= t.p_start and idx <= t.p_end) and step_bright or 1)
      if idx == edit_focus then screen.level(15) end
      
      local h = (s.pitch/127)*16
      screen.rect(fw_x, 40-h, w, h)
      screen.fill()
      fw_x = fw_x + w + 1
    end
  end
  
  -- Backward steps with velocity brightness
  local bw_x = center_x - (cur_w/2) - 2
  for i = 1, 10 do
    local idx = t.active_step - i
    if idx >= 1 and bw_x > 0 then
      local s = t.steps[idx]
      local w = math.max(2, (s.num/s.den)*4*sc)
      if idx == t.p_end then
        screen.level(10)
        screen.rect(bw_x-w, 23, w, 1)
        screen.fill()
        screen.move(bw_x, 40)
        screen.line_rel(0, -16)
        screen.stroke()
      end
      
      local ghost = params:get("ghost_thresh_"..selected_track)
      local step_bright = velocity_to_brightness(s.vel)
      
      -- Apply mute/solo dimming
      if track_mutes[selected_track] then
        step_bright = 3
      elseif track_solos[selected_track] then
        step_bright = step_bright
      else
        if step_bright == 0 then step_bright = 1 end
      end
      
      screen.level((idx >= t.p_start and idx <= t.p_end) and step_bright or 1)
      if idx == edit_focus then screen.level(15) end
      
      local h = (s.pitch/127)*16
      screen.rect(bw_x-w, 40-h, w, h)
      screen.fill()
      bw_x = bw_x - w - 1
    end
  end
  
  -- Divider line
  screen.level(1)
  screen.move(0, 42)
  screen.line(127, 42)
  screen.stroke()
  
  -- ZONE 4: CONTEXT BAR (y 43-48)
  screen.level(8)
  screen.move(8, 47)
  screen.text(groove_name)
  
  screen.level(6)
  screen.move(64, 47)
  screen.text_center(params:get("swing").."%")
  
  screen.level(6)
  screen.move(120, 47)
  local bpm = math.floor(60 / clock.get_beat_sec())
  screen.text_right(bpm.." BPM")
  
  screen.level(5)
  screen.move(8, 55)
  local ghost = params:get("ghost_thresh_"..selected_track)
  screen.text("Ghost:"..ghost.."%")
  
  -- ZONE 5: PARAMETER DISPLAY (y 44-62)
  local s = t.steps[edit_focus]
  local vals = {
    s.pitch .. " (" .. mu.note_num_to_name(s.pitch, true) .. ")",
    s.vel,
    s.num.."/"..s.den,
    s.cc1_v,
    s.cc2_v,
    s.mod,
    math.floor(s.artic*100).."%",
    s.glide,
    s.loop_to,
    s.repeats,
    s.prob.."%"
  }

  local start = util.clamp(param_focus - 1, 1, math.max(1, #param_names - 3))

  for i = 0, 3 do
    local idx = start + i
    if idx <= #param_names then
      local y = 50 + (i * 6)
      screen.level(param_focus == idx and 15 or 2)

      screen.move(8, y)
      local label = param_names[idx]
      if edit_focus == t.p_end and idx <= 2 then label = label .. "!" end
      screen.text(label)

      screen.move(122, y)

      if idx == 3 then
        local d_val = s.den
        local n_val = s.num

        screen.level(param_focus == 3 and (dur_sub_focus == 2 and 15 or 4) or 2)
        screen.text_right(d_val)

        local d_width = 10
        screen.move(122 - d_width, y)
        screen.level(param_focus == 3 and 15 or 2)
        screen.text_right("/")

        local s_width = 8
        screen.move(122 - d_width - s_width, y)
        screen.level(param_focus == 3 and (dur_sub_focus == 1 and 15 or 4) or 2)
        screen.text_right(n_val)
      else
        screen.text_right(vals[idx])
      end

      if param_focus == idx then
        screen.level(15)
        screen.move(2, y)
        screen.text(">")
      end
    end
  end
  
  -- TRANSIENT PARAMETER POPUP (level 15 for 0.8s)
  if popup_time > 0 and popup_param and popup_val then
    screen.level(15)
    screen.move(64, 20)
    screen.text_center(popup_param .. ": " .. popup_val)
  end
  
  screen.update()
  grid_redraw()
end

function cleanup()
  -- Stop all clocks and metros
  clock.cancel_all()

  -- Stop all running tracks and silence notes
  for i = 1, 4 do
    tracks[i].is_running = false
    if m then
      -- Send all-notes-off on each track's MIDI channel
      m:cc(123, 0, tracks[i].midi_ch)
    end
  end

  -- Send all-notes-off across all MIDI channels
  if m then
    for ch = 1, 16 do
      m:cc(123, 0, ch)
      m:cc(120, 0, ch)  -- also send reset
    end
  end

  -- Clear grid LEDs
  if g then
    g:all(0)
    g:refresh()
  end
end
