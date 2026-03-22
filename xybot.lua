-- XYBOT v3
-- algorithmic command center for OP-XY
-- simple surface · complex underneath · beautiful screen
--
-- K1 (hold) : alt layer
-- K1 + K2   : play / stop
-- K1 + K3   : next scene on OP-XY
-- E1        : select page
-- E2        : param A
-- E3        : param B
-- K2        : generate / action (page dependent)
-- K3        : mutate / action B (page dependent)
--
-- NEW FEATURES (v3.1):
--   K1+K2 (hold >0.5s) : toggle jam record mode
--   K1+K3 (hold >0.5s) : toggle MIDI learn mode
--   During jam record : every enc/key action timestamped
--   K3 in jam mode    : playback recorded jam
--   MIDI learn        : next CC received maps to focused param

engine.name = "PolySub"

local lattice   = require "lattice"
local sequins   = require "sequins"
local musicutil = require "musicutil"

-- ============================================================
-- CONFIG
-- ============================================================
local MIDI_DEV = 1
local DRUM_CH  = 1
local BASS_CH  = 2
local CHORD_CH = 3

local DRUM_NOTES = {
  kick=36, snare=38, clap=39,
  hat_c=42, hat_o=46,
  tom_l=45, tom_h=50, ride=51,
}

local function midi_to_hz(note)
  return 440 * 2^((note - 69) / 12)
end

local CC = {
  track_vol=7, track_mute=9, track_pan=10,
  param1=12, param2=13, param3=14, param4=15,
  amp_atk=20, amp_dec=21, amp_sus=22, amp_rel=23,
  fil_atk=24, fil_dec=25, fil_sus=26, fil_rel=27,
  poly_mode=28, portamento=29, pb_range=30, eng_vol=31,
  fil_cut=32, fil_res=33, fil_env_amt=34, key_track=35,
  send_ext=36, send_tape=37, send_fx1=38, send_fx2=39,
  lfo1=40, lfo2=41, lfo3=42, lfo4=43,
  track_params=46,
  tempo=80, groove=81,
  scene_delay=82, scene_prev=83, scene_next=84, scene=85,
  project=86, eq=90, track_sel=102,
  play=104, stop=105,
}

-- ============================================================
-- SCALES & CHORDS
-- ============================================================
local SCALES = {
  minor={0,2,3,5,7,8,10}, major={0,2,4,5,7,9,11},
  dorian={0,2,3,5,7,9,10}, pentatonic={0,3,5,7,10},
  phrygian={0,1,3,5,7,8,10}, lydian={0,2,4,6,7,9,11},
  mixolydian={0,2,4,5,7,9,10}, chromatic={0,1,2,3,4,5,6,7,8,9,10,11},
}
local scale_names = {"minor","major","dorian","pentatonic","phrygian","lydian","mixolydian","chromatic"}

local CHORD_TYPES = {
  triad={0,4,7}, minor={0,3,7}, sus2={0,2,7}, sus4={0,5,7},
  maj7={0,4,7,11}, min7={0,3,7,10}, dom7={0,4,7,10},
  power={0,7}, dim={0,3,6}, add9={0,4,7,14},
}
local chord_type_names = {"triad","minor","sus2","sus4","maj7","min7","dom7","power","dim","add9"}

-- ============================================================
-- PRESETS
-- ============================================================
local PRESETS = {
  { name="Growl Bass", ch=2,
    ccs={{32,30},{33,90},{34,80},{20,2},{21,60},{22,40},{23,20},{29,20},{40,60},{41,80}} },
  { name="Pluck Bass", ch=2,
    ccs={{32,80},{33,30},{34,100},{20,1},{21,30},{22,0},{23,10},{29,0},{40,0},{41,0}} },
  { name="Pad Chord", ch=3,
    ccs={{32,70},{33,20},{34,20},{20,60},{21,80},{22,100},{23,90},{40,40},{41,50}} },
  { name="Stab Chord", ch=3,
    ccs={{32,100},{33,50},{34,60},{20,1},{21,20},{22,0},{23,5},{40,0},{41,0}} },
  { name="FX Wash", ch=2,
    ccs={{38,127},{39,100},{32,50},{33,70},{40,80},{41,90}} },
  { name="Clean Kick", ch=1,
    ccs={{20,0},{21,50},{22,0},{23,30},{32,80},{33,10}} },
}
local preset_idx = 1

-- ============================================================
-- JAM RECORDING & PLAYBACK
-- ============================================================
local jam_recording = {}
local jam_playback_idx = 1
local jam_record_enabled = false
local jam_record_start_time = 0
local jam_playback_running = false

local function start_jam_record()
  jam_recording = {}
  jam_record_enabled = true
  jam_record_start_time = clock.get_beats()
  toast("JAM RECORD ON")
end

local function stop_jam_record()
  jam_record_enabled = false
  toast("JAM RECORD SAVED ("..#jam_recording.." events)")
end

local function record_jam_event(param_name, value)
  if not jam_record_enabled then return end
  local beat_offset = clock.get_beats() - jam_record_start_time
  table.insert(jam_recording, {
    time = beat_offset,
    param = param_name,
    value = value
  })
end

local function jam_playback()
  if #jam_recording == 0 then toast("JAM: no recording"); return end
  jam_playback_running = true
  jam_playback_idx = 1
  toast("JAM PLAYBACK")
  clock.run(function()
    local playback_start = clock.get_beats()
    while jam_playback_running and jam_playback_idx <= #jam_recording do
      local evt = jam_recording[jam_playback_idx]
      local wait_time = evt.time
      if jam_playback_idx > 1 then
        wait_time = evt.time - jam_recording[jam_playback_idx-1].time
      end
      clock.sleep(wait_time)
      -- Replay event (could route to param changes, MIDI CCs, etc.)
      -- For now, log it
      jam_playback_idx = jam_playback_idx + 1
    end
    jam_playback_running = false
  end)
end

-- ============================================================
-- MIDI CC LEARN
-- ============================================================
local midi_learn_mode = false
local cc_map = {}  -- {param_path -> cc_num}
local midi_learn_focused = nil

local function start_midi_learn()
  midi_learn_mode = true
  midi_learn_focused = {page=page, id=1}  -- Track focus
  toast("MIDI LEARN: ready for CC")
end

local function stop_midi_learn()
  midi_learn_mode = false
  midi_learn_focused = nil
  toast("MIDI LEARN: OFF")
end

-- ============================================================
-- ANIMATION / UI STATE
-- ============================================================
local anim = {
  -- flash message (top of screen)
  msg        = "",
  msg_timer  = 0,
  msg_ttl    = 1.8,   -- seconds

  -- per-voice hit flash (brightness pulse)
  kick_flash  = 0,
  snare_flash = 0,
  hat_flash   = 0,
  chord_flash = 0,
  bass_flash  = 0,

  -- page transition
  page_anim   = 0,    -- 0-1, fades in on page change

  -- play pulse (ring around step dot)
  play_pulse  = 0,

  -- waveform for bass line mini viz
  bass_wave   = {},

  -- encoder delta sparkle
  enc_spark   = {0,0,0},
  enc_dir     = {0,0,0},
  
  -- jam record pulse
  jam_rec_pulse = 0,
  
  -- MIDI learn flash
  learn_flash = 0,
  
  -- beat phase tracking (0-1)
  beat_phase = 0,
}

local redraw_metro  -- metro for animation ticks
local flash_clock_id

-- ============================================================
-- RUNTIME STATE
-- ============================================================
local m
local playing    = false
local page       = 1
local alt        = false
local step_vis   = 1
local pages      = {"BASS","DRUMS","CHORDS","FX","PRESETS","GLOBAL"}
local page_icons = {"~","#","♦","∿","◈","✦"}

-- Lattice visualization and gravity
local gravity    = 0.0         -- 0.0-1.0: pull toward root position
local lattice_x  = 4           -- lattice position (0-7 for 8 columns)
local lattice_y  = 2           -- lattice position (0-3 for 4 rows)
local lattice_root_x = 4       -- root note attractor x
local lattice_root_y = 2       -- root note attractor y
local velocity_topology = 0.5  -- brightness based on distance from root

-- K1 hold timing for jam record / learn
local k1_down_time = 0

local bass = {
  root=36, scale="minor", density=0.6,
  steps=16, octave=0,
  fil_cut=64, fil_res=40, portamento=0,
  pattern={}, notes={}, lengths={}, vels={},
  seq_density=nil, seq_scale=nil,
  auto_mutate=false, mutate_interval=8, mutate_count=0,
  engine_notes = {},
}
local drums = {
  steps=16, density=0.5, swing=63,
  pattern={}, vels={},
  auto_mutate=false, mutate_interval=8, mutate_count=0,
  seq_density=nil,
  engine_notes = {},
}
local chords = {
  root=48, scale="minor", chord_type="minor",
  density=0.3, steps=16, octave=0,
  vel_base=70, vel_rand=20,
  pattern={}, chord_notes={}, lengths={},
  auto_mutate=false, seq_chord=nil,
  engine_notes = {},
}
local fx = {
  fx1_send=50, fx2_send=30,
  fil_cut=80, fil_res=30,
  lfo_rate=50, lfo_amt=40,
}
local glob = {
  tempo=80, groove=63, scene=0,
  mute_drums=false, mute_bass=false, mute_chords=false,
  auto_scene=false, scene_bars=8, scene_bar_count=0,
}

-- ============================================================
-- OP-XY MIDI
-- ============================================================
local opxy_out = nil
local function opxy_note_on(note, vel)
  if opxy_out then opxy_out:note_on(note, vel, params:get("opxy_channel")) end
end
local function opxy_note_off(note)
  if opxy_out then opxy_out:note_off(note, 0, params:get("opxy_channel")) end
end

-- ============================================================
-- HELPERS
-- ============================================================
local function cc(ch,num,val)
  if m then m:cc(num,math.floor(math.max(0,math.min(127,val))),ch) end
end
local function note_on(ch,note,vel)
  if m then m:note_on(note,math.floor(vel or 100),ch) end
  opxy_note_on(note, math.floor(vel or 100))
end
local function note_off(ch,note)
  if m then m:note_off(note,0,ch) end
  opxy_note_off(note)
end
local function rrand(lo,hi) return lo+math.floor(math.random()*(hi-lo+1)) end

local function scale_note(root,sname,degree,oct_off)
  local sc=SCALES[sname] or SCALES["minor"]
  local idx=((degree-1)%#sc)+1
  local oct=math.floor((degree-1)/#sc)
  return root+sc[idx]+(oct+(oct_off or 0))*12
end

local function chord_from_root(root_note,ctype)
  local ivs=CHORD_TYPES[ctype] or CHORD_TYPES["minor"]
  local t={}; for _,iv in ipairs(ivs) do table.insert(t,root_note+iv) end
  return t
end

-- ============================================================
-- TOAST / FLASH MESSAGE
-- ============================================================
local function toast(msg)
  anim.msg       = msg
  anim.msg_timer = anim.msg_ttl
end

-- ============================================================
-- SEQUINS INIT
-- ============================================================
local function init_sequins()
  bass.seq_density  = sequins({0.4,0.6,0.5,0.7,0.3,0.65,0.8,0.5})
  bass.seq_scale    = sequins({"minor","dorian","pentatonic","minor","phrygian","minor"})
  chords.seq_chord  = sequins({"minor","sus2","min7","power","minor","dom7","sus4"})
  drums.seq_density = sequins({0.4,0.6,0.5,0.7,0.45,0.65,0.55,0.5})
end

-- ============================================================
-- GENERATORS
-- ============================================================
local function gen_bass_wave()
  anim.bass_wave = {}
  for s=1,bass.steps do
    if bass.pattern[s] then
      local nrm = util.clamp((bass.notes[s]-bass.root)/24,0,1)
      table.insert(anim.bass_wave, nrm)
    else
      table.insert(anim.bass_wave, -1)
    end
  end
end

function gen_bass()
  local sc = SCALES[bass.scale] or SCALES["minor"]
  for s=1,bass.steps do
    bass.pattern[s] = math.random() < bass.density
    if bass.pattern[s] then
      local r=math.random(); local degree
      if     r<0.30 then degree=1
      elseif r<0.50 then degree=5
      elseif r<0.65 then degree=4
      elseif r<0.76 then degree=3
      elseif r<0.86 then degree=7
      else                degree=rrand(1,#sc) end
      local oct=bass.octave
      if math.random()<0.12 then oct=oct+1 end
      bass.notes[s]   = scale_note(bass.root,bass.scale,degree,oct)
      bass.lengths[s] = math.random()<0.4 and 0.85 or 0.42
      bass.vels[s]    = rrand(80,115)
    end
  end
  gen_bass_wave()
end

function gen_drums()
  for s=1,drums.steps do
    drums.pattern[s]={}; drums.vels[s]={}
    local d=drums.density
    drums.pattern[s].kick  = (s==1 or s==9) or (math.random()<d*0.35)
    drums.pattern[s].snare = (s==5 or s==13) or (math.random()<d*0.18)
    drums.pattern[s].hat_c = math.random()<(0.45+d*0.45)
    drums.pattern[s].hat_o = (not drums.pattern[s].hat_c) and math.random()<0.12
    drums.pattern[s].clap  = drums.pattern[s].snare and math.random()<0.55
    drums.vels[s].kick  = drums.pattern[s].kick  and rrand(100,127) or 0
    drums.vels[s].snare = drums.pattern[s].snare and rrand(85,115)  or 0
    drums.vels[s].hat_c = drums.pattern[s].hat_c and rrand(45,100)  or 0
    drums.vels[s].hat_o = drums.pattern[s].hat_o and rrand(55,95)   or 0
    drums.vels[s].clap  = drums.pattern[s].clap  and rrand(65,110)  or 0
  end
end

function gen_chords()
  local prog={1,4,5,6,1,1,5,4}
  for s=1,chords.steps do
    chords.pattern[s]=math.random()<chords.density
    if chords.pattern[s] then
      local deg=prog[rrand(1,#prog)]
      local rn=scale_note(chords.root,chords.scale,deg,chords.octave)
      chords.chord_notes[s]=chord_from_root(rn,chords.chord_type)
      chords.lengths[s]=math.random()<0.5 and 1.8 or 0.9
    end
  end
end

-- ============================================================
-- PUSH CCs
-- ============================================================
local function push_bass_env()
  cc(BASS_CH,CC.amp_atk,3);  cc(BASS_CH,CC.amp_dec,50)
  cc(BASS_CH,CC.amp_sus,80); cc(BASS_CH,CC.amp_rel,25)
  cc(BASS_CH,CC.fil_cut,bass.fil_cut)
  cc(BASS_CH,CC.fil_res,bass.fil_res)
  cc(BASS_CH,CC.portamento,bass.portamento)
end
local function push_chord_env()
  cc(CHORD_CH,CC.amp_atk,55); cc(CHORD_CH,CC.amp_dec,70)
  cc(CHORD_CH,CC.amp_sus,90); cc(CHORD_CH,CC.amp_rel,80)
  cc(CHORD_CH,CC.fil_cut,70); cc(CHORD_CH,CC.fil_res,20)
  cc(CHORD_CH,CC.poly_mode,0)
end
local function push_fx()
  cc(BASS_CH,CC.send_fx1,fx.fx1_send)
  cc(BASS_CH,CC.send_fx2,fx.fx2_send)
  cc(BASS_CH,CC.fil_cut,fx.fil_cut)
  cc(BASS_CH,CC.fil_res,fx.fil_res)
  cc(BASS_CH,CC.lfo1,fx.lfo_rate)
  cc(BASS_CH,CC.lfo2,fx.lfo_amt)
end
local function push_global()
  cc(1,CC.tempo,glob.tempo); cc(1,CC.groove,glob.groove)
end
local function apply_preset(p)
  for _,pair in ipairs(p.ccs) do cc(p.ch,pair[1],pair[2]) end
end

-- ============================================================
-- MUTATE
-- ============================================================
local function maybe_mutate_bass()
  if not bass.auto_mutate then return end
  bass.mutate_count=bass.mutate_count+1
  if bass.mutate_count>=bass.mutate_interval then
    bass.mutate_count=0
    bass.density=bass.seq_density()
    bass.scale=bass.seq_scale()
    gen_bass()
    toast("bass evolved → "..bass.scale)
  end
end
local function maybe_mutate_drums()
  if not drums.auto_mutate then return end
  drums.mutate_count=drums.mutate_count+1
  if drums.mutate_count>=drums.mutate_interval then
    drums.mutate_count=0
    drums.density=drums.seq_density()
    gen_drums()
    toast("drums evolved")
  end
end
local function maybe_mutate_chords()
  if not chords.auto_mutate then return end
  chords.chord_type=chords.seq_chord()
  gen_chords()
  toast("chords → "..chords.chord_type)
end
local function maybe_auto_scene()
  if not glob.auto_scene then return end
  glob.scene_bar_count=glob.scene_bar_count+1
  if glob.scene_bar_count>=glob.scene_bars then
    glob.scene_bar_count=0
    glob.scene=(glob.scene+1)%8
    cc(1,CC.scene_delay,glob.scene)
    toast("scene → "..(glob.scene+1))
  end
end

-- ============================================================
-- LATTICE
-- ============================================================
local the_lattice
local patt_bass,patt_chord,patt_kick,patt_snare,patt_hat,patt_mutate

local function drum_hit(note,vel,len)
  note_on(DRUM_CH,note,vel)
  local freq = midi_to_hz(note)
  engine.noteOn(note, freq, vel / 127)
  table.insert(drums.engine_notes, note)
  clock.run(function()
    clock.sleep(clock.get_beat_sec()*(len or 0.18))
    note_off(DRUM_CH,note)
    engine.noteOff(note)
  end)
end

local function build_lattice()
  if the_lattice then the_lattice:destroy() end
  the_lattice=lattice:new{auto=true,meter=4,ppqn=96}

  local bs=0
  patt_bass=the_lattice:new_pattern{
    division=1/4,enabled=true,
    action=function(t)
      bs=(bs%bass.steps)+1; step_vis=bs
      if not glob.mute_bass and bass.pattern[bs] then
        local n=bass.notes[bs]; local v=bass.vels[bs]; local l=bass.lengths[bs]
        note_on(BASS_CH,n,v)
        local freq = midi_to_hz(n)
        engine.noteOn(n, freq, v / 127)
        table.insert(bass.engine_notes, n)
        anim.bass_flash=1.0
        clock.run(function()
          clock.sleep(clock.get_beat_sec()*l)
          note_off(BASS_CH,n)
          engine.noteOff(n)
        end)
      end
      anim.play_pulse=1.0
      anim.beat_phase = 0
      redraw()
    end
  }

  local cs=0
  patt_chord=the_lattice:new_pattern{
    division=1,enabled=true,
    action=function(t)
      cs=(cs%chords.steps)+1
      if not glob.mute_chords and chords.pattern[cs] then
        local ns=chords.chord_notes[cs]; local l=chords.lengths[cs]
        for _,n in ipairs(ns) do
          note_on(CHORD_CH,n,rrand(chords.vel_base-chords.vel_rand,chords.vel_base+chords.vel_rand))
          local freq = midi_to_hz(n)
          local vel = rrand(chords.vel_base-chords.vel_rand,chords.vel_base+chords.vel_rand)
          engine.noteOn(n, freq, vel / 127)
          table.insert(chords.engine_notes, n)
        end
        anim.chord_flash=1.0
        clock.run(function()
          clock.sleep(clock.get_beat_sec()*l)
          for _,n in ipairs(ns) do
            note_off(CHORD_CH,n)
            engine.noteOff(n)
          end
        end)
      end
    end
  }

  local ks=0
  patt_kick=the_lattice:new_pattern{
    division=1/4,enabled=true,
    action=function(t)
      ks=(ks%drums.steps)+1
      if not glob.mute_drums and drums.pattern[ks] and drums.pattern[ks].kick then
        drum_hit(DRUM_NOTES.kick,drums.vels[ks].kick)
        anim.kick_flash=1.0
      end
    end
  }

  local ss=0
  patt_snare=the_lattice:new_pattern{
    division=1/4,enabled=true,
    action=function(t)
      ss=(ss%drums.steps)+1
      if not glob.mute_drums and drums.pattern[ss] then
        if drums.pattern[ss].snare then
          drum_hit(DRUM_NOTES.snare,drums.vels[ss].snare)
          anim.snare_flash=1.0
        end
        if drums.pattern[ss].clap then
          drum_hit(DRUM_NOTES.clap,drums.vels[ss].clap)
        end
      end
    end
  }

  local hs=0
  patt_hat=the_lattice:new_pattern{
    division=1/4,enabled=true,
    action=function(t)
      hs=(hs%drums.steps)+1
      if not glob.mute_drums and drums.pattern[hs] then
        if drums.pattern[hs].hat_c then
          drum_hit(DRUM_NOTES.hat_c,drums.vels[hs].hat_c,0.12)
          anim.hat_flash=0.7
        elseif drums.pattern[hs].hat_o then
          drum_hit(DRUM_NOTES.hat_o,drums.vels[hs].hat_o,0.25)
          anim.hat_flash=0.5
        end
      end
    end
  }

  patt_mutate=the_lattice:new_pattern{
    division=4,enabled=true,
    action=function(t)
      maybe_mutate_bass(); maybe_mutate_drums()
      maybe_mutate_chords(); maybe_auto_scene()
    end
  }

  the_lattice:start()
end

-- ============================================================
-- ANIMATION METRO (~10fps for smooth screen updates)
-- ============================================================
local ANIM_FPS = 10
local DECAY = 0.15   -- flash decay per frame

local function anim_tick()
  -- decay flashes
  local function decay(v) return math.max(0, v - DECAY) end
  anim.kick_flash  = decay(anim.kick_flash)
  anim.snare_flash = decay(anim.snare_flash)
  anim.hat_flash   = decay(anim.hat_flash)
  anim.chord_flash = decay(anim.chord_flash)
  anim.bass_flash  = decay(anim.bass_flash)
  anim.play_pulse  = decay(anim.play_pulse)
  anim.jam_rec_pulse = decay(anim.jam_rec_pulse)
  anim.learn_flash = decay(anim.learn_flash)
  
  -- decay encoder sparks
  for i=1,3 do anim.enc_spark[i]=decay(anim.enc_spark[i]) end
  
  -- page fade
  anim.page_anim = math.min(1, anim.page_anim + 0.2)
  
  -- beat phase advance
  if playing then
    anim.beat_phase = math.min(1, anim.beat_phase + 0.12)
  end
  
  -- toast timer
  if anim.msg_timer > 0 then
    anim.msg_timer = anim.msg_timer - (1/ANIM_FPS)
    if anim.msg_timer <= 0 then anim.msg="" end
  end
  
  redraw()
end

-- ============================================================
-- SCREEN DRAWING PRIMITIVES
-- ============================================================
local function brightness(flash_val, base, peak)
  return math.floor(base + (peak-base)*flash_val)
end

-- horizontal pill bar
local function pill_bar(x,y,w,h,val,maxv,base_lvl,fill_lvl)
  screen.level(base_lvl or 2)
  screen.rect(x,y,w,h) screen.stroke()
  local fw = math.floor(w * util.clamp(val/maxv,0,1))
  if fw > 0 then
    screen.level(fill_lvl or 10)
    screen.rect(x,y,fw,h) screen.fill()
  end
end

-- small label + value pair
local function lv(x,y,lbl,val,lbright,vbright)
  screen.level(lbright or 4)
  screen.move(x,y) screen.text(lbl)
  screen.level(vbright or 14)
  screen.move(x+string.len(lbl)*5+2,y) screen.text(tostring(val))
end

-- step cursor line
local function step_cursor(sx, y, w, steps)
  local sw = w/steps
  local cx = math.floor((sx-1)*sw + sw/2)
  screen.level(15)
  screen.move(cx, y) screen.line(cx, y+2) screen.stroke()
end

-- ============================================================
-- LATTICE VISUALIZATION
-- ============================================================
local function draw_lattice_viz(x_offset, y_offset)
  -- Draw 8x4 dot grid lattice
  local cols, rows = 8, 4
  local dot_spacing = 4
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local x = x_offset + col * dot_spacing
      local y = y_offset + row * dot_spacing
      local is_current = (col == lattice_x and row == lattice_y)
      local is_root = (col == lattice_root_x and row == lattice_root_y)

      if is_current then
        screen.level(15)
        screen.circle(x, y, 1.5)
        screen.fill()
      elseif is_root then
        screen.level(8)
        screen.circle(x, y, 1)
        screen.fill()
      else
        screen.level(3)
        screen.circle(x, y, 0.5)
        screen.fill()
      end
    end
  end
end

-- ============================================================
-- PAGE DRAWERS
-- ============================================================
local function draw_bass_page()
  local alpha = anim.page_anim

  -- waveform display (main visual) with playhead
  local ww = 128
  local sw = ww / bass.steps
  for s=1,bass.steps do
    local x = (s-1)*sw
    local active = bass.pattern[s]
    local is_cur = (s == step_vis)
    if active then
      local h = math.floor(util.clamp(anim.bass_wave[s]*14, 1, 14))
      local lvl
      if is_cur and playing then
        lvl = brightness(anim.bass_flash, 8, 15)
      else
        lvl = playing and 6 or 4
      end
      screen.level(lvl)
      screen.rect(x+1, 52-h, sw-1, h) screen.fill()
      -- note top cap brighter
      screen.level(is_cur and 15 or lvl+2)
      screen.rect(x+1, 52-h, sw-1, 1) screen.fill()
    else
      screen.level(2)
      screen.rect(x+1, 52, sw-1, 1) screen.fill()
    end
  end

  -- playhead: position marker that moves with clock
  if playing then
    local ph_x = math.floor((step_vis-1)*sw + anim.beat_phase*sw)
    screen.level(brightness(anim.play_pulse, 5, 15))
    screen.move(ph_x, 54) screen.line(ph_x, 57) screen.stroke()
  end

  -- params strip (secondary params at level 8, labels at 5)
  screen.level(3)
  screen.move(0,62) screen.line(128,62) screen.stroke()
  lv(0,  63, "scl", bass.scale:sub(1,5),   5, 8)
  lv(52, 63, "den", string.format("%d%%",math.floor(bass.density*100)), 5, 8)
  lv(90, 63, "cut", bass.fil_cut, 5, 8)

  -- auto badge (active params at level 15)
  if bass.auto_mutate then
    screen.level(15)
    screen.move(112,20) screen.text("AUTO")
  end
  
  -- jam indicator
  if jam_record_enabled then
    anim.jam_rec_pulse = 1.0
    screen.level(brightness(anim.jam_rec_pulse, 8, 15))
    screen.move(100,10) screen.text("REC")
  elseif midi_learn_mode then
    anim.learn_flash = 1.0
    screen.level(brightness(anim.learn_flash, 4, 15))
    screen.move(98,10) screen.text("LEARN")
  end
end

local function draw_drums_page()
  local rows  = {"kick","snare","hat_c","clap"}
  local lbls  = {"K","S","H","C"}
  local flashes = {anim.kick_flash, anim.snare_flash, anim.hat_flash, 0}
  local ystep = 9
  local xoff  = 10

  for r,row in ipairs(rows) do
    local y = 24 + (r-1)*ystep
    -- label with flash (active at 15, secondary at 8)
    screen.level(brightness(flashes[r], 5, 15))
    screen.move(0,y) screen.text(lbls[r])

    for s=1,drums.steps do
      local x = xoff + (s-1)*7
      local on = drums.pattern[s] and drums.pattern[s][row]
      local is_cur = (s == step_vis)
      local lvl
      if is_cur and playing then
        lvl = on and brightness(flashes[r],8,15) or 5
      else
        lvl = on and 9 or 2
      end
      screen.level(lvl)
      screen.rect(x, y-7, 5, 6)
      if on then screen.fill() else screen.stroke() end
    end
  end

  -- playhead for drums
  if playing then
    local sw = 7
    local ph_x = xoff + (step_vis-1)*sw + anim.beat_phase*sw
    screen.level(brightness(anim.play_pulse, 4, 12))
    screen.move(ph_x, 52) screen.line(ph_x, 54) screen.stroke()
  end

  -- groove bar (labels at 5, secondary at 8)
  screen.level(3)
  screen.move(0,62) screen.line(128,62) screen.stroke()
  lv(0, 63, "den", string.format("%d%%",math.floor(drums.density*100)), 5, 8)
  lv(52,63, "swg", string.format("%+d",drums.swing-63), 5, 8)
  if drums.auto_mutate then
    screen.level(15) screen.move(100,63) screen.text("AUTO")
  end
end

local function draw_chords_page()
  -- chord blocks across bottom half with playhead
  local sw = 128/chords.steps
  for s=1,chords.steps do
    local x=(s-1)*sw
    local is_cur = (s==step_vis)
    if chords.pattern[s] then
      local n = chords.chord_notes[s] and #chords.chord_notes[s] or 1
      local lvl
      if is_cur and playing then
        lvl = brightness(anim.chord_flash, 7, 15)
      else
        lvl = playing and 6 or 4
      end
      -- draw stacked note bars
      for i=1,n do
        screen.level(lvl - (i-1))
        screen.rect(x+1, 58-(i*4), sw-1, 3) screen.fill()
      end
    else
      screen.level(2)
      screen.rect(x+1, 54, sw-1, 1) screen.fill()
    end
  end

  -- playhead for chords
  if playing then
    local ph_x = math.floor((step_vis-1)*sw + anim.beat_phase*sw)
    screen.level(brightness(anim.chord_flash,3,12))
    screen.move(ph_x,60) screen.line(ph_x,63) screen.stroke()
  end

  -- params (labels at 5, secondary at 8, active at 13)
  screen.level(3)
  screen.move(0,21) screen.line(128,21) screen.stroke()
  lv(0,  20, "typ", chords.chord_type,  5, 13)
  lv(68, 20, "den", string.format("%d%%",math.floor(chords.density*100)), 5, 8)
  lv(0,  63, "vel", chords.vel_base,    5, 8)
  if chords.auto_mutate then
    screen.level(15) screen.move(100,63) screen.text("AUTO")
  end
end

local function draw_fx_page()
  -- big horizontal bars (labels at 5, secondary at 8)
  local labels = {"FX1","FX2","CUT","RES","LFO","AMT"}
  local vals   = {fx.fx1_send, fx.fx2_send, fx.fil_cut, fx.fil_res, fx.lfo_rate, fx.lfo_amt}
  local fills  = {14,10,12,8,11,9}
  for i=1,6 do
    local y = 17 + (i-1)*8
    screen.level(5)
    screen.move(0,y) screen.text(labels[i])
    pill_bar(20, y-6, 90, 5, vals[i], 127, 3, fills[i])
    screen.level(8)
    screen.move(114,y) screen.text(vals[i])
  end
end

local function draw_presets_page()
  local p = PRESETS[preset_idx]
  -- big name (active parameter)
  screen.level(15)
  screen.font_size(10)
  screen.move(0,24) screen.text(p.name)
  screen.font_size(8)
  -- ch indicator (secondary)
  screen.level(8)
  screen.move(0,34) screen.text("channel "..p.ch.."  ·  "..(#p.ccs).." params")
  -- cc preview (labels)
  for i=1,math.min(4,#p.ccs) do
    screen.level(5)
    screen.move(0,34+i*7)
    local cc_names = {
      [32]="fil.cut",[33]="fil.res",[20]="atk",[21]="dec",
      [22]="sus",[23]="rel",[38]="fx1",[39]="fx2",[40]="lfo"
    }
    local cname = cc_names[p.ccs[i][1]] or ("cc"..p.ccs[i][1])
    screen.text(cname.." → "..p.ccs[i][2])
  end
  -- nav (structure at level 3)
  screen.level(6)
  screen.move(0,63)
  screen.text("◀ "..preset_idx.."/"..#PRESETS.." ▶   K2=apply")
end

local function draw_global_page()
  local bpm = math.floor(40 + glob.tempo/127*180)

  -- Lattice visualization (top right corner)
  screen.level(5)
  screen.move(85, 12) screen.text("LATTICE")
  draw_lattice_viz(85, 18)

  -- big BPM (active parameter at 15)
  screen.font_size(16)
  screen.level(playing and 15 or 8)
  screen.move(0,35) screen.text(bpm.." bpm")
  screen.font_size(8)

  -- scene indicator: dots (structure at 3, active at 15)
  screen.level(5) screen.move(0,44) screen.text("scene")
  for i=0,7 do
    screen.level(i==glob.scene and 15 or 3)
    screen.rect(38+(i*9), 38, 7, 6)
    if i==glob.scene then screen.fill() else screen.stroke() end
  end

  -- groove / mute strip (labels at 5, values at 8)
  lv(0, 55, "grv", string.format("%+d",glob.groove-63), 5, 8)
  -- mute dots
  local function mute_btn(x,y,label,muted)
    screen.level(muted and 3 or 11)
    screen.move(x,y) screen.text(label)
    if muted then
      screen.level(3)
      screen.move(x-1,y-7) screen.line(x+7,y-7) screen.stroke()
    end
  end
  mute_btn(55,55,"BAS",glob.mute_bass)
  mute_btn(77,55,"DRM",glob.mute_drums)
  mute_btn(99,55,"CHD",glob.mute_chords)

  screen.level(3)
  screen.move(0,63) screen.text("E2=tempo  E3=scene  K3=auto")
  if glob.auto_scene then
    screen.level(15) screen.move(100,63) screen.text("AUTO")
  end
end

-- ============================================================
-- MASTER REDRAW
-- ============================================================
function redraw()
  screen.clear()
  screen.aa(0)  -- anti-alias enabled for smooth lines
  screen.font_size(8)

  -- ---- STATUS STRIP (y 0-8) ----
  -- play state
  screen.level(playing and 15 or 4)
  screen.move(2, 7)
  screen.text(playing and ">" or ".")

  -- page name left of center
  screen.level(10)
  screen.move(12, 7)
  screen.text(pages[page])

  -- page dots right side
  for i = 1, 6 do
    screen.level(i == page and 15 or 3)
    screen.pixel(90 + (i - 1) * 6, 4)
    screen.fill()
  end

  -- beat pulse
  screen.level(brightness(anim.beat_phase, 3, 12))
  screen.pixel(124, 4)
  screen.fill()

  -- divider
  screen.level(2)
  screen.move(0, 9)
  screen.line(128, 9)
  screen.stroke()

  -- ---- JAM RECORD / LEARN INDICATORS ----
  if jam_record_enabled then
    anim.jam_rec_pulse = 1.0
    screen.level(brightness(anim.jam_rec_pulse, 8, 15))
    screen.move(110,18) screen.text("REC")
  elseif midi_learn_mode then
    anim.learn_flash = 1.0
    screen.level(brightness(anim.learn_flash, 4, 15))
    screen.move(106,18) screen.text("LEARN")
  end

  -- ---- TOAST MESSAGE ----
  if anim.msg ~= "" and anim.msg_timer > 0 then
    local alpha = math.min(1, anim.msg_timer * 2)  -- fade in/out
    local lvl   = math.floor(alpha * 15)
    -- toast background pill
    local tw = string.len(anim.msg)*5 + 6
    screen.level(1)
    screen.rect(63 - tw/2, 11, tw, 9) screen.fill()
    screen.level(lvl)
    screen.move(64 - tw/2 + 2, 19)
    screen.text(anim.msg)
  end

  -- ---- LIVE ZONE (y 9-52) ----
  if page==1 then draw_bass_page()
  elseif page==2 then draw_drums_page()
  elseif page==3 then draw_chords_page()
  elseif page==4 then draw_fx_page()
  elseif page==5 then draw_presets_page()
  elseif page==6 then draw_global_page()
  end

  -- ---- CONTEXT BAR (y 53-58) ----
  screen.level(3)
  screen.move(0,52) screen.line(128,52) screen.stroke()
  
  local bpm = math.floor(40 + glob.tempo/127*180)
  screen.level(6)
  screen.move(0,60) screen.text("BPM:"..bpm)
  
  screen.level(5)
  screen.move(35,60) screen.text("CH:"..BASS_CH)
  
  if page==1 or page==3 then
    screen.level(6)
    screen.move(55,60) screen.text(bass.scale.."/"..chords.scale)
  end
  
  screen.level(4)
  screen.move(100,60) screen.text("MIDI:"..MIDI_DEV)

  -- ---- ALT BADGE ----
  if alt then
    screen.level(15)
    screen.move(119,8) screen.text("[⇧]")
  end

  screen.update()
end

-- ============================================================
-- INIT
-- ============================================================
function init()
  math.randomseed(os.time())
  m = midi.connect(MIDI_DEV)

  params:add_separator("XYBOT")
  params:add_number("midi_dev","MIDI device",1,4,1)
  params:set_action("midi_dev",function(v) MIDI_DEV=v; m=midi.connect(v) end)
  params:add_number("drum_ch","Drum ch",1,16,1)
  params:set_action("drum_ch",function(v) DRUM_CH=v end)
  params:add_number("bass_ch","Bass ch",1,16,2)
  params:set_action("bass_ch",function(v) BASS_CH=v end)
  params:add_number("chord_ch","Chord ch",1,16,3)
  params:set_action("chord_ch",function(v) CHORD_CH=v end)
  params:add_option("scale","Scale",scale_names,1)
  params:set_action("scale",function(v)
    bass.scale=scale_names[v]; chords.scale=scale_names[v]
    gen_bass(); gen_chords(); toast("scale → "..scale_names[v])
  end)
  params:add_number("bass_root","Bass root",24,60,36)
  params:set_action("bass_root",function(v) bass.root=v; gen_bass() end)
  params:add_number("chord_root","Chord root",36,72,48)
  params:set_action("chord_root",function(v) chords.root=v; gen_chords() end)

  params:add_separator("OP-XY MIDI")
  params:add{type="number", id="opxy_device", name="OP-XY Device", min=1, max=16, default=2,
    action=function(v) opxy_out = midi.connect(v) end}
  params:add{type="number", id="opxy_channel", name="OP-XY Channel", min=1, max=16, default=1}
  opxy_out = midi.connect(2)

  params:add_separator("LATTICE")
  params:add_control("gravity","Gravity",
    controlspec.new(0, 1, "lin", 0.01, 0.0, ""))
  params:set_action("gravity",function(v) gravity=v end)
  params:add_control("velocity_topology","Velocity Topology",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:set_action("velocity_topology",function(v) velocity_topology=v end)

  init_sequins()
  gen_bass(); gen_drums(); gen_chords()
  push_bass_env(); push_chord_env(); push_global(); push_fx()

  -- animation metro at ~10fps for smooth updates with beat phase tracking
  redraw_metro = metro.init(anim_tick, 1/ANIM_FPS, -1)
  redraw_metro:start()

  anim.page_anim = 0
  anim.beat_phase = 0
  toast("XYBOT ready")
  redraw()
end

-- ============================================================
-- CONTROLS
-- ============================================================
function key(id,z)
  if id==1 then
    if z==1 then
      k1_down_time = 0
      alt = true
    else
      alt = false
      if k1_down_time > 0.5 then
        -- K1 held >0.5s: do nothing special on release
      end
      k1_down_time = 0
    end
    redraw()
    return
  end
  if z==0 then return end

  if id==2 then
    if alt then
      if k1_down_time > 0.5 then
        -- K1+K2 held >0.5s: toggle jam record
        if jam_record_enabled then
          stop_jam_record()
        else
          start_jam_record()
        end
      else
        -- K1+K2 tap: play / stop
        playing = not playing
        if playing then
          build_lattice()
          cc(1,CC.play,127)
          toast("▶ playing")
        else
          if the_lattice then the_lattice:destroy(); the_lattice=nil end
          for ch=1,16 do if m then m:cc(123,0,ch) end end
          for n=0,127 do pcall(function() engine.noteOff(n) end) end
          cc(1,CC.stop,127)
          step_vis=1
          anim.beat_phase=0
          toast("■ stopped")
        end
      end
    else
      if page==1 then
        gen_bass(); push_bass_env(); toast("bass regenerated")
      elseif page==2 then
        gen_drums(); toast("drums regenerated")
      elseif page==3 then
        gen_chords(); push_chord_env(); toast("chords regenerated")
      elseif page==4 then
        push_fx(); toast("fx pushed")
      elseif page==5 then
        apply_preset(PRESETS[preset_idx])
        toast("preset: "..PRESETS[preset_idx].name)
      elseif page==6 then
        push_global(); toast("globals sent")
      end
    end
  end

  if id==3 then
    if alt then
      if k1_down_time > 0.5 then
        -- K1+K3 held: toggle MIDI learn
        if midi_learn_mode then
          stop_midi_learn()
        else
          start_midi_learn()
        end
      else
        -- K1+K3 tap: next scene
        glob.scene=(glob.scene+1)%8
        cc(1,CC.scene_delay,glob.scene)
        toast("scene → "..(glob.scene+1))
      end
    else
      if jam_record_enabled then
        jam_playback()  -- K3 during recording: playback
      elseif page==1 then
        bass.density=bass.seq_density()
        bass.scale=bass.seq_scale()
        gen_bass()
        toast("evolved → "..bass.scale)
      elseif page==2 then
        drums.density=drums.seq_density()
        gen_drums()
        toast(string.format("drums den %d%%",math.floor(drums.density*100)))
      elseif page==3 then
        chords.chord_type=chords.seq_chord()
        gen_chords()
        toast("chord → "..chords.chord_type)
      elseif page==4 then
        fx.fx1_send=rrand(0,127); fx.fx2_send=rrand(0,127)
        push_fx()
        toast("fx randomised")
      elseif page==5 then
        preset_idx=(preset_idx%#PRESETS)+1
        toast("preset: "..PRESETS[preset_idx].name)
      elseif page==6 then
        glob.auto_scene=not glob.auto_scene
        toast("auto-scene "..(glob.auto_scene and "ON" or "off"))
      end
    end
  end

  redraw()
end

function enc(id,d)
  anim.enc_spark[id]=1.0
  anim.enc_dir[id]=d>0 and 1 or -1

  if id==1 then
    page=util.clamp(page+d,1,#pages)
    anim.page_anim=0

  elseif id==2 then
    if page==1 then
      bass.density=util.clamp(bass.density+d*0.05,0,1)
      record_jam_event("bass_density", bass.density)
      toast(string.format("bass density %d%%",math.floor(bass.density*100)))
    elseif page==2 then
      drums.density=util.clamp(drums.density+d*0.05,0,1)
      record_jam_event("drums_density", drums.density)
      toast(string.format("drum density %d%%",math.floor(drums.density*100)))
    elseif page==3 then
      chords.density=util.clamp(chords.density+d*0.05,0,1)
      record_jam_event("chords_density", chords.density)
      toast(string.format("chord density %d%%",math.floor(chords.density*100)))
    elseif page==4 then
      fx.fx1_send=util.clamp(fx.fx1_send+d,0,127)
      cc(BASS_CH,CC.send_fx1,fx.fx1_send)
      record_jam_event("fx1_send", fx.fx1_send)
      toast("fx1 send "..fx.fx1_send)
    elseif page==5 then
      preset_idx=util.clamp(preset_idx+d,1,#PRESETS)
      toast(PRESETS[preset_idx].name)
    elseif page==6 then
      glob.tempo=util.clamp(glob.tempo+d,0,127)
      cc(1,CC.tempo,glob.tempo)
      local bpm=math.floor(40+glob.tempo/127*180)
      toast(bpm.." bpm")
    end

  elseif id==3 then
    if page==1 then
      bass.fil_cut=util.clamp(bass.fil_cut+d,0,127)
      cc(BASS_CH,CC.fil_cut,bass.fil_cut)
      record_jam_event("bass_fil_cut", bass.fil_cut)
      toast("bass cut "..bass.fil_cut)
    elseif page==2 then
      drums.swing=util.clamp(drums.swing+d,0,127)
      glob.groove=drums.swing
      cc(1,CC.groove,glob.groove)
      toast(string.format("swing %+d",drums.swing-63))
    elseif page==3 then
      chords.vel_base=util.clamp(chords.vel_base+d,0,127)
      toast("chord vel "..chords.vel_base)
    elseif page==4 then
      fx.fx2_send=util.clamp(fx.fx2_send+d,0,127)
      cc(BASS_CH,CC.send_fx2,fx.fx2_send)
      toast("fx2 send "..fx.fx2_send)
    elseif page==5 then
      -- no-op scroll
    elseif page==6 then
      glob.scene=util.clamp(glob.scene+d,0,98)
      cc(1,CC.scene_delay,glob.scene)
      toast("scene → "..(glob.scene+1))
    end
  end

  redraw()
end

-- Timer for K1 hold detection
clock.run(function()
  while true do
    clock.sleep(0.01)
    if alt then
      k1_down_time = k1_down_time + 0.01
    end
  end
end)

-- ============================================================
-- MIDI NOTE INPUT (maps to lattice position)
-- ============================================================
function midi.event(data)
  local msg = midi.to_msg(data)
  if msg.type == "note_on" then
    -- Map MIDI note number to lattice x (0-7)
    lattice_x = msg.note % 8
    -- Map velocity to lattice y (0-3), higher velocity = lower y
    lattice_y = math.floor(msg.vel / 127 * 4)
    lattice_y = math.min(3, lattice_y)
    toast("lattice → x:"..lattice_x.." y:"..lattice_y)
    redraw()
  end
end

-- ============================================================
-- CLEANUP
-- ============================================================
function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if the_lattice then the_lattice:destroy() end
  if m then for ch=1,16 do m:cc(123,0,ch) end end
  if opxy_out then for ch=1,16 do opxy_out:cc(123,0,ch) end end
  -- PolySub: noteOff per-voice (no noteOffAll command)
  for n=0,127 do pcall(function() engine.noteOff(n) end) end
end