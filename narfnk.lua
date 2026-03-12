-- NARFNK: Quad Sequential
--         Funk Machine
--
--      4 Channels of
--    99-Step Stochastic
--     MIDI Funk Sequencing
--
-- K1 (Hold) + E1:
--      Select Track
--      (BASS, KEYS, GUIT, HORN)
-- E1: Select Step
-- E2: Select Parameter
-- E3: Adjust Parameter
--
-- Parameter details:
--
-- DURATION: E2 toggles between
--     Numerator/Denominator.
--     E3 adjusts.
--
-- CC1/CC2: Assignable MIDI CC.
--     Select CC address and
--     value separately.
--
-- K1 + K3: GLOBAL START / STOP
--
-- K3 (Hold):
--     SAVE to selected SLOT.
--     Slots are handled
--     externally in PARAMS.
--
-- K3 (Tap): Randomize step
--     with funk flavor

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

local param_names = {"PITCH", "VELOCITY", "DURATION", "CC1 VALUE", "CC2 VALUE", "MODULATION", "ARTICULATION", "GLIDE", "LOOP TO", "REPEATS", "PROBABILITY"}
local m = midi.connect()

-- FUNK DEFAULTS per track role
-- pitch_lo/hi: randomize range, default_vel, default_artic
local funk_defaults = {
  -- BASS: low register, strong attack, tight articulation
  { pitch_lo = 28, pitch_hi = 52, vel = 110, artic = 0.70, den = 4 },
  -- KEYS: mid register, moderate velocity, staccato stabs
  { pitch_lo = 55, pitch_hi = 79, vel = 90, artic = 0.40, den = 4 },
  -- GUIT: mid register, tight 16th chops
  { pitch_lo = 48, pitch_hi = 72, vel = 85, artic = 0.35, den = 4 },
  -- HORN: upper register, punchy stabs
  { pitch_lo = 60, pitch_hi = 84, vel = 100, artic = 0.50, den = 4 },
}

-- GROOVE TEMPLATES
-- Each template is a table of 16 steps: {pitch_offset, vel, num, den, artic, prob}
-- pitch_offset is relative to root (0 = root, 7 = fifth, etc.)
-- vel 0 = rest/ghost

local groove_templates = {
  -- 1: Parliament One — everything hits the ONE hard
  { name = "Parliament 1",
    steps = {
      {0,120,1,4,0.8,100}, {0,0,1,4,0.5,0},     {7,70,1,4,0.4,80},  {0,50,1,4,0.3,60},
      {5,100,1,4,0.7,100}, {0,0,1,4,0.5,0},      {7,65,1,4,0.35,70}, {3,45,1,4,0.3,50},
      {0,110,1,4,0.75,100},{0,0,1,4,0.5,0},       {5,75,1,4,0.4,85},  {7,40,1,4,0.25,40},
      {3,95,1,4,0.65,100}, {0,0,1,4,0.5,0},       {5,60,1,4,0.35,70}, {0,55,1,4,0.3,60},
    }
  },
  -- 2: JB Tight — James Brown precision pocket
  { name = "JB Tight",
    steps = {
      {0,127,1,4,0.6,100}, {0,40,1,4,0.2,50},    {7,90,1,4,0.5,100}, {0,35,1,4,0.2,40},
      {5,110,1,4,0.55,100},{0,45,1,4,0.2,50},     {3,85,1,4,0.45,90}, {0,30,1,4,0.15,30},
      {0,115,1,4,0.6,100}, {0,40,1,4,0.2,45},     {7,95,1,4,0.5,100}, {0,35,1,4,0.2,40},
      {5,105,1,4,0.55,100},{0,50,1,4,0.25,55},    {3,80,1,4,0.4,85},  {7,60,1,4,0.3,70},
    }
  },
  -- 3: Sly Syncopated — Sly Stone off-beat groove
  { name = "Sly Synco",
    steps = {
      {0,110,1,4,0.7,100}, {5,85,1,4,0.4,90},    {0,0,1,4,0.5,0},    {7,100,1,4,0.6,100},
      {0,0,1,4,0.5,0},     {3,90,1,4,0.5,95},     {0,50,1,4,0.3,50},  {5,105,1,4,0.65,100},
      {0,0,1,4,0.5,0},     {7,80,1,4,0.4,80},     {0,100,1,4,0.6,100},{0,0,1,4,0.5,0},
      {3,95,1,4,0.55,100}, {0,45,1,4,0.25,45},    {5,90,1,4,0.5,90},  {0,0,1,4,0.5,0},
    }
  },
  -- 4: Bootsy Bass — deep pocket with octave pops
  { name = "Bootsy Bass",
    steps = {
      {0,120,1,4,0.75,100},{0,0,1,4,0.5,0},      {0,50,1,4,0.25,50}, {12,90,1,4,0.4,90},
      {0,0,1,4,0.5,0},     {0,100,1,4,0.6,100},   {0,0,1,4,0.5,0},    {7,70,1,4,0.35,75},
      {0,115,1,4,0.7,100}, {12,80,1,4,0.35,85},   {0,0,1,4,0.5,0},    {0,55,1,4,0.3,55},
      {5,105,1,4,0.6,100}, {0,0,1,4,0.5,0},       {7,65,1,4,0.3,65},  {0,75,1,4,0.4,80},
    }
  },
  -- 5: Meters Groove — The Meters second-line funk
  { name = "Meters",
    steps = {
      {0,115,1,4,0.65,100},{0,40,1,4,0.2,40},    {5,80,1,4,0.45,85}, {0,0,1,4,0.5,0},
      {7,100,1,4,0.6,100}, {0,50,1,4,0.25,55},   {0,0,1,4,0.5,0},    {3,90,1,4,0.5,95},
      {0,110,1,4,0.6,100}, {0,0,1,4,0.5,0},      {5,85,1,4,0.45,90}, {7,45,1,4,0.2,45},
      {0,0,1,4,0.5,0},     {3,95,1,4,0.55,100},   {0,55,1,4,0.3,60},  {5,70,1,4,0.35,75},
    }
  },
  -- 6: Stevie Wonder — clavinet-style 16th chop
  { name = "Stevie Clav",
    steps = {
      {0,100,1,4,0.3,100}, {3,75,1,4,0.25,80},   {5,90,1,4,0.3,95},  {0,50,1,4,0.2,50},
      {7,95,1,4,0.3,100},  {3,55,1,4,0.2,55},    {0,85,1,4,0.3,90},  {5,60,1,4,0.2,60},
      {0,105,1,4,0.3,100}, {7,70,1,4,0.25,75},   {3,90,1,4,0.3,95},  {0,45,1,4,0.2,45},
      {5,100,1,4,0.3,100}, {0,65,1,4,0.2,65},    {7,80,1,4,0.25,85}, {3,50,1,4,0.2,50},
    }
  },
  -- 7: Prince — minimal but locked
  { name = "Prince",
    steps = {
      {0,120,1,4,0.5,100}, {0,0,1,4,0.5,0},      {0,0,1,4,0.5,0},    {7,80,1,4,0.35,80},
      {0,0,1,4,0.5,0},     {0,100,1,4,0.5,100},   {0,0,1,4,0.5,0},    {0,0,1,4,0.5,0},
      {5,110,1,4,0.5,100}, {0,0,1,4,0.5,0},       {7,70,1,4,0.3,70},  {0,0,1,4,0.5,0},
      {0,95,1,4,0.45,100}, {3,60,1,4,0.25,60},    {0,0,1,4,0.5,0},    {5,85,1,4,0.4,90},
    }
  },
  -- 8: P-Funk Mothership — polyrhythmic cosmic groove
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

  clock.run(function()
    while true do
      if flash_level > 0 then flash_level = flash_level - 1; redraw() end
      clock.sleep(1/15)
    end
  end)

  params:add_separator("narfnk_config", "NARFNK CONFIG")
  params:add_number("save_slot", "SAVE/LOAD SLOT", 1, 10, 1)
  params:set_action("save_slot", function(v) load_sequence(v) end)

  params:add_option("send_clock", "SEND MIDI CLOCK", {"OFF", "ON"}, 2)
  params:add_option("rec_mode", "MIDI RECORD MODE", {"OFF", "ON"}, 1)
  params:add_option("midi_remote", "REMOTE MAPPING", {"OFF", "16n", "nKONTROL2"}, 2)

  -- FUNK: Global Swing (50% = straight, 67% = triplet swing)
  params:add_control("swing", "SWING",
    controlspec.new(50, 75, 'lin', 1, 54, "%"))

  -- FUNK: Groove template loader per track
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
    -- FUNK: Ghost note threshold per track
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
    redraw()
  end)

  params:add_separator("quantize_config", "QUANTIZATION")
  -- FUNK: Default quantize ON, Mixolydian (the funk mode)
  params:add_option("quantize", "QUANTIZE", {"OFF", "ON"}, 2)
  params:add_option("root_note", "ROOT NOTE", mu.NOTE_NAMES, 1)
  local scale_names = {}
  for i=1, #mu.SCALES do table.insert(scale_names, mu.SCALES[i].name) end
  -- Find Mixolydian index
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
  end

  load_sequence(params:get("save_slot"))
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

-- FUNK: Apply a groove template to a track
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
  -- Set pattern end to template length
  t.p_end = #tmpl.steps
  params:set("end_"..track_idx, #tmpl.steps)
  print("NARFNK: Loaded " .. tmpl.name .. " on " .. track_names[track_idx])
  redraw()
end

-- 3. REMOTE MIDI HANDLER
function handle_remote_cc(cc, val, mode)
  if mode == 2 then
    if cc >= 32 and cc <= 35 then tracks[cc-31].steps[edit_focus].pitch = val
    elseif cc >= 36 and cc <= 39 then tracks[cc-35].steps[edit_focus].vel = val
    elseif cc >= 40 and cc <= 43 then tracks[cc-39].steps[edit_focus].num = util.clamp(math.floor(val/4)+1, 1, 32)
    elseif cc >= 44 and cc <= 47 then tracks[cc-43].steps[edit_focus].mod = val end
  end
  redraw()
end

-- FUNK: Calculate swing delay for a given step
-- Even-numbered steps (2, 4, 6...) get pushed later
-- swing_pct: 50 = straight, 67 = triplet feel
local function get_swing_delay(step_in_bar, total_sleep)
  local swing_pct = params:get("swing") / 100
  -- Only apply swing to even 16th notes (steps 2, 4, 6, 8...)
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

    -- FUNK: Probability check — skip step if probability fails
    if math.random(1, 100) > s.prob then
      -- Rest: still sleep for the duration to keep time
      local dur_beats = (s.num / s.den) * 4
      local total_sleep = dur_beats * clock.get_beat_sec()
      -- Apply swing even on rests to keep pocket
      local step_in_bar = ((t.active_step - 1) % 16) + 1
      local swing_delay = get_swing_delay(step_in_bar, total_sleep)
      if swing_delay > 0 then clock.sleep(swing_delay) end
      clock.sleep(total_sleep - swing_delay)
    else
      -- FUNK: Ghost note detection — if vel below ghost threshold, play softer
      local ghost_thresh = params:get("ghost_thresh_"..t_idx)
      local play_vel = s.vel
      if s.vel > 0 and s.vel < ghost_thresh then
        play_vel = math.floor(s.vel * 0.5) -- ghosts are half velocity
      end

      if s.glide > 0 then m:cc(65, 127, t.midi_ch); m:cc(5, s.glide, t.midi_ch) end
      if t.cc1_n > 0 then m:cc(t.cc1_n, s.cc1_v, t.midi_ch) end
      if t.cc2_n > 0 then m:cc(t.cc2_n, s.cc2_v, t.midi_ch) end

      t.is_playing_note = true
      m:note_on(final_pitch, play_vel, t.midi_ch)
      m:cc(1, s.mod, t.midi_ch)

      local dur_beats = (s.num / s.den) * 4
      local total_sleep = dur_beats * clock.get_beat_sec()

      -- FUNK: Apply swing
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

    -- Advance step
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
    if param_focus == 1 then s.pitch = util.clamp(s.pitch + d, 0, 127)
    elseif param_focus == 2 then s.vel = util.clamp(s.vel + d, 0, 127)
    elseif param_focus == 3 then
      if dur_sub_focus == 1 then s.num = util.clamp(s.num + d, 1, 32) else s.den = util.clamp(s.den + d, 1, 32) end
    elseif param_focus == 4 then s.cc1_v = util.clamp(s.cc1_v + d, 0, 127)
    elseif param_focus == 5 then s.cc2_v = util.clamp(s.cc2_v + d, 0, 127)
    elseif param_focus == 6 then s.mod = util.clamp(s.mod + d, 0, 127)
    elseif param_focus == 7 then s.artic = util.clamp(s.artic + (d * 0.05), 0.05, 1)
    elseif param_focus == 8 then s.glide = util.clamp(s.glide + d, 0, 127)
    elseif param_focus == 9 then s.loop_to = util.clamp(s.loop_to + d, 0, 99)
    elseif param_focus == 10 then s.repeats = util.clamp(s.repeats + d, 0, 16)
    elseif param_focus == 11 then s.prob = util.clamp(s.prob + d, 0, 100)
    end
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
    if shift then if z == 1 then global_toggle() end
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

-- FUNK: Funk-aware randomize with syncopation + ghost notes
function funk_randomize_step(t, i)
  local fd = funk_defaults[t]
  local step = tracks[t].steps[i]
  local step_in_bar = ((i - 1) % 16) + 1

  -- Pitch: use track's funk range, quantized
  step.pitch = get_quantized_note(math.random(fd.pitch_lo, fd.pitch_hi))

  -- Velocity: emphasize the ONE and syncopated accents
  if step_in_bar == 1 then
    -- THE ONE: always strong
    step.vel = math.random(110, 127)
    step.prob = 100
  elseif step_in_bar == 5 or step_in_bar == 9 or step_in_bar == 13 then
    -- Beat 2, 3, 4 downbeats: moderately strong
    step.vel = math.random(85, 110)
    step.prob = math.random(85, 100)
  elseif step_in_bar % 2 == 0 then
    -- Even 16ths (swing targets): mix of accents and ghosts
    if math.random() > 0.5 then
      step.vel = math.random(70, 100) -- accent
      step.prob = math.random(70, 95)
    else
      step.vel = math.random(25, 50) -- ghost note
      step.prob = math.random(40, 70)
    end
  else
    -- Odd off-beats: funkiest zone - syncopation lives here
    if math.random() > 0.3 then
      step.vel = math.random(60, 100)
      step.prob = math.random(60, 90)
    else
      step.vel = 0 -- rest
      step.prob = 0
    end
  end

  -- Articulation: tight for funk, varies by position
  if step_in_bar == 1 then
    step.artic = math.random(60, 80) / 100
  else
    step.artic = math.random(20, 55) / 100
  end

  -- Duration: always 16th note grid
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

-- 7. REDRAW
function redraw()
  if show_splash then draw_splash(); return end
  screen.clear()
  if flash_level > 0 then screen.level(flash_level); screen.rect(0,0,128,64); screen.fill() end
  for i=1,4 do
    screen.level(selected_track == i and 15 or 2)
    local name_w = #track_names[i] * 5 + 2
    screen.move((i-1)*32, 7); screen.text(track_names[i])
    if tracks[i].is_running then screen.rect((i-1)*32, 8, name_w, 1); screen.fill() end
  end
  screen.font_size(8)
  screen.font_face(2)
  screen.level(3); screen.move(127, 7); screen.text_right("S:"..params:get("save_slot").." P:"..tracks[selected_track].active_step.." E:"..edit_focus)
  local t = tracks[selected_track]; local center_x, sc = 64, 12
  local is_last_step = (t.active_step == t.p_end); local cur_s = t.steps[t.active_step]
  local cur_w = math.max(2, (cur_s.num/cur_s.den)*4*sc); screen.level(is_last_step and 15 or 12)
  local bar_h = (cur_s.pitch/127)*16; screen.rect(center_x-(cur_w/2), 32-bar_h, cur_w, bar_h); screen.fill()
  if is_last_step then screen.level(15); screen.move(center_x, 12); screen.line_rel(-2,-2); screen.line_rel(4,0); screen.line_rel(-2,2); screen.fill() end
  local fw_x = center_x + (cur_w/2) + 2
  screen.font_face(1)
  screen.font_size(8)
  for i = 1, 10 do
    local idx = t.active_step + i; if idx <= 99 and fw_x < 128 then
      local s = t.steps[idx]; local w = math.max(2, (s.num/s.den)*4*sc)
      if idx == t.p_end then screen.level(10); screen.rect(fw_x, 15, w, 1); screen.fill(); screen.move(fw_x + w, 32); screen.line_rel(0, -16); screen.stroke() end
      -- FUNK: Ghost notes drawn dimmer
      local ghost = params:get("ghost_thresh_"..selected_track)
      local step_bright = 2
      if s.vel > 0 and s.vel < ghost then step_bright = 1 end
      screen.level((idx >= t.p_start and idx <= t.p_end) and step_bright or 1); if idx == edit_focus then screen.level(5) end
      local h = (s.pitch/127)*16; screen.rect(fw_x, 32-h, w, h); screen.fill(); fw_x = fw_x + w + 1
    end
  end
  local bw_x = center_x - (cur_w/2) - 2
  for i = 1, 10 do
    local idx = t.active_step - i; if idx >= 1 and bw_x > 0 then
      local s = t.steps[idx]; local w = math.max(2, (s.num/s.den)*4*sc)
      if idx == t.p_end then screen.level(10); screen.rect(bw_x-w, 15, w, 1); screen.fill(); screen.move(bw_x, 32); screen.line_rel(0, -16); screen.stroke() end
      local ghost = params:get("ghost_thresh_"..selected_track)
      local step_bright = 2
      if s.vel > 0 and s.vel < ghost then step_bright = 1 end
      screen.level((idx >= t.p_start and idx <= t.p_end) and step_bright or 1); if idx == edit_focus then screen.level(5) end
      local h = (s.pitch/127)*16; screen.rect(bw_x-w, 32-h, w, h); screen.fill(); bw_x = bw_x - w - 1
    end
  end
  screen.level(1); screen.move(0, 36); screen.line(127, 36); screen.stroke()
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
      local y = 44 + (i * 6)
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
  screen.update()
end

function cleanup()
  for i = 1, 4 do
    tracks[i].is_running = false
  end
  if m then
    for ch = 1, 16 do
      m:cc(123, 0, ch)
    end
  end
  clock.cancel_all()
end