require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.view.inputmethod.*"
import "android.text.*"
import "android.content.*"
import "android.graphics.*"
import "android.graphics.drawable.*"
import "android.media.*"
import "android.net.*"
import "android.provider.*"
import "java.io.*"
import "java.net.*"
import "java.util.*"

local APP_TITLE = "AI Voice Cloner Studio"
local APP_DEV = "Developer: Abdul Rehman"
local FEEDBACK_PHONE = "923124255300"

-- Internal private cache & internal favorites directory (Never auto-saves to Download folder)
local CACHE_DIR = tostring(activity.getCacheDir().getAbsolutePath())
local WORK_DIR = CACHE_DIR .. "/voice_cloner_work"
local FAV_DIR = tostring(activity.getFilesDir().getAbsolutePath()) .. "/favorite_voices"
local FAV_INDEX_FILE = FAV_DIR .. "/favorites.txt"
local TEMP_RECORD_FILE = WORK_DIR .. "/temp_recorded_sample.m4a"
local TEMP_CLONED_FILE = WORK_DIR .. "/temp_cloned_output.wav"
local STATUS_FILE = WORK_DIR .. "/status.txt"

-- Public Download directory (Used ONLY when user taps DOWNLOAD button)
local PUBLIC_DOWNLOAD_DIR = "/storage/emulated/0/Download"

File(WORK_DIR).mkdirs()
File(FAV_DIR).mkdirs()
File(PUBLIC_DOWNLOAD_DIR).mkdirs()

local state = {
  refAudioPath = "",
  refDisplayName = "",
  langIndex = 1,
  emotionIndex = 1,
  speedIndex = 3,
  isGenerating = false,
  isRecording = false,
  generatedAudioPath = "",
  customFileName = "",
  outputPlayer = nil,
  isOutputPlaying = false,
  isOutputPaused = false,
  samplePlayer = nil,
  isSamplePlaying = false,
  browserPreviewPlayer = nil,
  browserPreviewPath = "",
  browserPreviewPaused = false,
  activePreviewBtn = nil,
  recorder = nil,
  activeTicker = nil
}

local LANGUAGES = {
  { name = "Auto Detect (Urdu & English)", code = "Auto", xtts = "hi" },
  { name = "Urdu (اردو)", code = "Auto", xtts = "hi" },
  { name = "English", code = "Auto", xtts = "en" },
  { name = "Hindi", code = "Auto", xtts = "hi" },
  { name = "Arabic", code = "Auto", xtts = "ar" },
  { name = "Punjabi", code = "Auto", xtts = "hi" }
}

local EMOTIONS = {
  { name = "Natural & Balanced (Default)", instruct = "", speedMul = 1.00 },
  { name = "Happy & Cheerful (خوشگوار)", instruct = "Happy, cheerful, warm and smiling tone", speedMul = 1.03 },
  { name = "Sad & Emotional (اداس اور جذباتی)", instruct = "Sad, emotional, soft and heartfelt tone", speedMul = 0.92 },
  { name = "Heartbroken & Crying (غمگین لہجہ)", instruct = "Deeply sorrowful, tearful, trembling emotional voice", speedMul = 0.88 },
  { name = "Angry & Intense (غصے والا انداز)", instruct = "Angry, intense, firm and forceful tone", speedMul = 1.05 },
  { name = "Storytelling & Novel (کہانی اور ناول)", instruct = "Expressive storytelling narrator voice with natural drama", speedMul = 0.96 },
  { name = "Dramatic & Cinematic (ڈرامائی انداز)", instruct = "Dramatic, theatrical, deep cinematic expression", speedMul = 0.95 },
  { name = "Suspense & Mystery (سسپنس اور پراسرار)", instruct = "Low pitch, mysterious, tense suspenseful voice", speedMul = 0.90 },
  { name = "Whisper & Soft Secret (سرگوشی)", instruct = "Whisper, soft, quiet and intimate voice", speedMul = 0.92 },
  { name = "News Anchor & Broadcast (نیوز اینکر)", instruct = "Clear, professional, articulate news broadcast tone", speedMul = 1.02 },
  { name = "Documentary Narrator (ڈاکومنٹری انداز)", instruct = "Deep, informative, engaging documentary narrator", speedMul = 0.97 },
  { name = "Islamic & Respectful (ادب اور روحانی انداز)", instruct = "Calm, respectful, dignified and soulful tone", speedMul = 0.93 },
  { name = "Poetry & Shayari (شاعری کا انداز)", instruct = "Poetic, lyrical, emotional and rhythmic delivery", speedMul = 0.90 },
  { name = "Motivational & Energetic (پرجوش اور باہمت)", instruct = "Inspiring, powerful, energetic and confident voice", speedMul = 1.05 },
  { name = "Calm & Soothing (پرسکون اور دھیما)", instruct = "Peaceful, gentle, slow and soothing voice", speedMul = 0.91 },
  { name = "Serious & Authoritative (سنجیدہ اور باوقار)", instruct = "Serious, firm, commanding and authoritative voice", speedMul = 0.97 },
  { name = "Fearful & Nervous (خوفزدہ لہجہ)", instruct = "Breathless, anxious, fearful and shaky voice", speedMul = 1.04 },
  { name = "Excited & Surprised (حیران اور پرجوش)", instruct = "High energy, excited, amazed and lively voice", speedMul = 1.08 },
  { name = "Friendly Conversation (دوستانہ گفتگو)", instruct = "Warm, casual, natural everyday friendly conversation", speedMul = 1.00 },
  { name = "Deep & Commanding (بھاری اور رعب دار)", instruct = "Very low pitch, deep resonant and powerful voice", speedMul = 0.94 }
}

local SPEEDS = {
  { name = "0.85x (Slow & Deep)", val = 0.85 },
  { name = "0.95x (Calm Natural)", val = 0.95 },
  { name = "1.00x (Normal Human)", val = 1.00 },
  { name = "1.10x (Dynamic)", val = 1.10 },
  { name = "1.20x (Fast)", val = 1.20 }
}

-- ============================================================================
-- 35ms Haptic Vibration + Studio Chime Sound Generator (Start & Stop Recording)
-- ============================================================================
local vibratorService = nil
pcall(function()
  vibratorService = activity.getSystemService(Context.VIBRATOR_SERVICE)
end)

local function vibrate35ms()
  pcall(function()
    if vibratorService then
      if Build.VERSION.SDK_INT >= 26 then
        local VibrationEffect = luajava.bindClass("android.os.VibrationEffect")
        vibratorService.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
      else
        vibratorService.vibrate(35)
      end
    end
  end)
end

-- Vibrate 35ms on launch
vibrate35ms()

local function playRecordStudioChime(isStartChime)
  pcall(function()
    local ByteBuffer = luajava.bindClass("java.nio.ByteBuffer")
    local ByteOrder = luajava.bindClass("java.nio.ByteOrder")
    local sampleRate = 24000
    local totalSamples = math.floor(sampleRate * 0.22)
    local bb = ByteBuffer.allocate(totalSamples * 2)
    bb.order(ByteOrder.LITTLE_ENDIAN)

    local freq1 = isStartChime and 587.33 or 880.00
    local freq2 = isStartChime and 880.00 or 523.25
    local half = math.floor(totalSamples * 0.48)

    for i = 0, totalSamples - 1 do
      local f = (i < half) and freq1 or freq2
      local localIdx = (i < half) and i or (i - half)
      local localLen = (i < half) and half or (totalSamples - half)
      local env = math.sin((localIdx / localLen) * math.pi)
      local decay = math.exp(-3.0 * (localIdx / localLen))
      local t = i / sampleRate
      local wave = (math.sin(2 * math.pi * f * t) * 0.75) + (math.sin(4 * math.pi * f * t) * 0.25)
      local sampleVal = math.floor(wave * env * decay * 18000)
      bb.putShort(sampleVal)
    end

    local pcmBytes = bb.array()
    local track = AudioTrack(
      AudioManager.STREAM_MUSIC,
      sampleRate,
      AudioFormat.CHANNEL_OUT_MONO,
      AudioFormat.ENCODING_PCM_16BIT,
      #pcmBytes,
      AudioTrack.MODE_STATIC
    )
    track.write(pcmBytes, 0, #pcmBytes)
    track.play()

    Handler().postDelayed(Runnable{
      run = function()
        pcall(function()
          track.stop()
          track.release()
        end)
      end
    }, 300)
  end)
end

local function speakText(msg)
  local s = tostring(msg or "")
  pcall(function()
    if service and service.speak then
      service.speak(s)
      return
    end
  end)
  Toast.makeText(activity, s, Toast.LENGTH_SHORT).show()
end

-- ============================================================================
-- Favorite Voices Storage Manager
-- ============================================================================
local function loadFavoritesList()
  local list = {}
  pcall(function()
    local f = io.open(FAV_INDEX_FILE, "r")
    if not f then return end
    for line in f:lines() do
      local title, path = line:match("^([^|]+)|(.+)$")
      if title and path and File(path).exists() then
        table.insert(list, { name = title, path = path })
      end
    end
    f:close()
  end)
  return list
end

local function saveFavoritesList(list)
  pcall(function()
    local f = io.open(FAV_INDEX_FILE, "w")
    if not f then return end
    for _, item in ipairs(list) do
      if item.name and item.path and File(item.path).exists() then
        f:write(tostring(item.name) .. "|" .. tostring(item.path) .. "\n")
      end
    end
    f:close()
  end)
end

-- ============================================================================
-- UI Styling Helpers: Double-Bordered Luxury Cards, Headings & Rich Dialogs
-- ============================================================================
local function makeBorderDrawable(fillHex, borderHex, radiusDp, strokePx)
  local gd = GradientDrawable()
  gd.setShape(GradientDrawable.RECTANGLE)
  gd.setColor(Color.parseColor(fillHex))
  gd.setCornerRadius(radiusDp or 22)
  if borderHex then
    gd.setStroke(strokePx or 5, Color.parseColor(borderHex))
  end
  return gd
end

local function makeDividerBar(colorHex, heightPx, marginBottomPx)
  local v = View(activity)
  v.setBackgroundColor(Color.parseColor(colorHex))
  v.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO)
  local lp = LinearLayout.LayoutParams(
    LinearLayout.LayoutParams.MATCH_PARENT,
    heightPx or 4
  )
  lp.setMargins(0, 6, 0, marginBottomPx or 12)
  v.setLayoutParams(lp)
  return v
end

local function markAsHeading(tv)
  pcall(function()
    tv.setFocusable(true)
    tv.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES)
    if Build.VERSION.SDK_INT >= 28 then
      tv.setAccessibilityHeading(true)
    end
  end)
end

local function markAsFocusableText(tv)
  pcall(function()
    tv.setFocusable(true)
    tv.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES)
  end)
end

local function createFramedCard(outerBorderHex, innerFillHex, radiusDp, borderThicknessPx, padH, padV, marginBottomPx)
  local outer = LinearLayout(activity)
  outer.setOrientation(LinearLayout.VERTICAL)
  local bPx = borderThicknessPx or 5
  outer.setPadding(bPx, bPx, bPx, bPx)
  outer.setBackgroundColor(Color.parseColor(outerBorderHex))
  outer.setBackground(makeBorderDrawable(outerBorderHex, outerBorderHex, radiusDp or 24, bPx))

  local lp = LinearLayout.LayoutParams(
    LinearLayout.LayoutParams.MATCH_PARENT,
    LinearLayout.LayoutParams.WRAP_CONTENT
  )
  lp.setMargins(0, 0, 0, marginBottomPx or 22)
  outer.setLayoutParams(lp)

  local inner = LinearLayout(activity)
  inner.setOrientation(LinearLayout.VERTICAL)
  inner.setPadding(padH or 24, padV or 22, padH or 24, padV or 22)
  inner.setBackgroundColor(Color.parseColor(innerFillHex))
  inner.setBackground(makeBorderDrawable(innerFillHex, outerBorderHex, (radiusDp or 24) - 4, 2))
  inner.setLayoutParams(LinearLayout.LayoutParams(
    LinearLayout.LayoutParams.MATCH_PARENT,
    LinearLayout.LayoutParams.WRAP_CONTENT
  ))

  outer.addView(inner)
  return outer, inner
end

local function styleActionButton(btn, fillHex, borderHex, textHex, radiusDp, padH, padV)
  btn.setTextColor(Color.parseColor(textHex or "#FFFFFF"))
  btn.setTypeface(Typeface.DEFAULT_BOLD)
  btn.setAllCaps(false)
  btn.setPadding(padH or 18, padV or 18, padH or 18, padV or 18)
  btn.setBackgroundColor(Color.parseColor(fillHex))
  btn.setBackground(makeBorderDrawable(fillHex, borderHex, radiusDp or 18, 4))
end

local function showRichDialog(rootView, borderHex, bgHex)
  local dlg = AlertDialog.Builder(activity)
    .setView(rootView)
    .create()
  dlg.show()
  pcall(function()
    local win = dlg.getWindow()
    if win then
      win.setBackgroundDrawable(makeBorderDrawable(bgHex or "#070E1A", borderHex or "#00E5FF", 30, 6))
      local dm = activity.getResources().getDisplayMetrics()
      win.setLayout(math.floor(dm.widthPixels * 0.95), WindowManager.LayoutParams.WRAP_CONTENT)
    end
  end)
  return dlg
end

-- ============================================================================
-- Smart Urdu Pronunciation, Diacritics & Grammar Normalizer
-- ============================================================================
local URDU_PRONUNCIATION_MAP = {
  ["کتا"] = "کُتّا",
  ["کتے"] = "کُتّے",
  ["کتوں"] = "کُتّوں",
  ["کتیا"] = "کُتیا",
  ["محبت"] = "مُحَبَّت",
  ["خوبصورت"] = "خُوبصُورَت",
  ["مشکل"] = "مُشکِل",
  ["شکریہ"] = "شُکرِیہ",
  ["دعا"] = "دُعا",
  ["خدا"] = "خُدا",
  ["مجھے"] = "مُجھے",
  ["تمہیں"] = "تُمہیں",
  ["تمہارا"] = "تُمہارا",
  ["تمہاری"] = "تُمہاری",
  ["تمہارے"] = "تُمہارے",
  ["انہوں"] = "اُنہوں",
  ["انھوں"] = "اُنہوں",
  ["کچھ"] = "کُچھ",
  ["بہت"] = "بَہُت",
  ["صبح"] = "صُبح",
  ["شروع"] = "شُروع",
  ["گفتگو"] = "گُفتگُو",
  ["دنیا"] = "دُنیا",
  ["اردو"] = "اُردُو",
  ["بالکل"] = "بِلکُل",
  ["سچ"] = "سَچّ",
  ["بچہ"] = "بَچّہ",
  ["بچے"] = "بَچّے",
  ["بچوں"] = "بَچّوں",
  ["اچھا"] = "اَچّھا",
  ["اچھی"] = "اَچّھی",
  ["اچھے"] = "اَچّھے",
  ["چپ"] = "چُپ",
  ["سن"] = "سُن",
  ["سنا"] = "سُنا",
  ["سنو"] = "سُنو",
  ["روکو"] = "رُوکو",
  ["غصہ"] = "غُصّہ",
  ["غصے"] = "غُصّے",
  ["عزت"] = "عِزَّت",
  ["قسمت"] = "قِسمَت",
  ["ضرورت"] = "ضَرورَت",
  ["ضروری"] = "ضَروری",
  ["حکومت"] = "حُکومَت",
  ["مکمل"] = "مُکَمَّل",
  ["مسلسل"] = "مُسَلسَل",
  ["تعلق"] = "تَعَلُّق",
  ["توجہ"] = "تَوَجُّہ",
  ["امید"] = "اُمّید",
  ["استعمال"] = "اِستِعمال",
  ["انتظار"] = "اِنتِظار",
  ["اعتبار"] = "اِعتِبار",
  ["اختیار"] = "اِختِیار",
  ["انسان"] = "اِنسان",
  ["انسانی"] = "اِنسانی"
}

local function normalizeUrduScript(rawText)
  local s = tostring(rawText or "")
  s = s:gsub("ك", "ک"):gsub("ي", "ی"):gsub("ى", "ی"):gsub("ۀ", "ہ"):gsub("ة", "ہ")
  s = s:gsub("۔", " ۔ ")
  s = s:gsub("؟", " ؟ ")
  s = s:gsub("،", " ، ")
  s = s:gsub("%s+", " ")

  local outWords = {}
  for w in s:gmatch("%S+") do
    local cleanW = w:gsub("[۔،؟%!%?%.%,%:%;\"\'%(%)]", "")
    local replacement = URDU_PRONUNCIATION_MAP[cleanW]
    if replacement and cleanW ~= "" then
      local fixed = w:gsub(cleanW, replacement, 1)
      table.insert(outWords, fixed)
    else
      table.insert(outWords, w)
    end
  end
  local result = table.concat(outWords, " ")
  result = result:gsub("%s+([۔،؟%!%?])", "%1")
  result = result:gsub("^%s+", ""):gsub("%s+$", "")
  return result
end

local wakeLock = nil
local function acquireWakeLock()
  pcall(function()
    if not wakeLock then
      local pm = activity.getSystemService(Context.POWER_SERVICE)
      wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AIVoiceCloner::WakeLock")
    end
    if wakeLock and not wakeLock.isHeld() then
      wakeLock.acquire(10 * 60 * 1000)
    end
  end)
end

local function releaseWakeLock()
  pcall(function()
    if wakeLock and wakeLock.isHeld() then
      wakeLock.release()
    end
  end)
end

local function stopProgressTicker()
  pcall(function()
    if state.activeTicker then
      state.activeTicker.stop()
    end
  end)
  state.activeTicker = nil
end

local btnPlaySample, btnAddFavorite, sampleActionRow
local btnPlayPauseOutput, btnDownloadOutput, btnRenameOutput
local tvSampleStatus, tvOutputStatus, tvProgressStatus, progressBar, outputControlsOuter

local function stopBrowserPreview()
  pcall(function()
    if state.browserPreviewPlayer then
      if state.browserPreviewPlayer.isPlaying() then
        state.browserPreviewPlayer.stop()
      end
      state.browserPreviewPlayer.release()
    end
  end)
  if state.activePreviewBtn then
    pcall(function()
      state.activePreviewBtn.setText("Play")
      styleActionButton(state.activePreviewBtn, "#059669", "#34D399", "#FFFFFF", 16, 22, 14)
    end)
  end
  state.browserPreviewPlayer = nil
  state.browserPreviewPath = ""
  state.browserPreviewPaused = false
  state.activePreviewBtn = nil
end

local function stopSamplePlayback()
  pcall(function()
    if state.samplePlayer then
      if state.samplePlayer.isPlaying() then
        state.samplePlayer.stop()
      end
      state.samplePlayer.release()
    end
  end)
  state.samplePlayer = nil
  state.isSamplePlaying = false
  if btnPlaySample then
    btnPlaySample.setText("PLAY SAMPLE")
    styleActionButton(btnPlaySample, "#1E293B", "#38BDF8", "#FFFFFF", 18, 14, 18)
  end
end

local function stopOutputPlayback()
  pcall(function()
    if state.outputPlayer then
      if state.outputPlayer.isPlaying() then
        state.outputPlayer.stop()
      end
      state.outputPlayer.release()
    end
  end)
  state.outputPlayer = nil
  state.isOutputPlaying = false
  state.isOutputPaused = false
  if btnPlayPauseOutput then
    btnPlayPauseOutput.setText("PLAY")
    styleActionButton(btnPlayPauseOutput, "#1D4ED8", "#60A5FA", "#FFFFFF", 18, 12, 20)
  end
end

-- ============================================================================
-- MAIN WINDOW UI (Royal Obsidian Navy with Double Neon Borders & Rich Padding)
-- ============================================================================
local rootScroll = ScrollView(activity)
rootScroll.setFillViewport(true)
rootScroll.setBackgroundColor(Color.parseColor("#040814"))

local screenWrapper = LinearLayout(activity)
screenWrapper.setOrientation(LinearLayout.VERTICAL)
screenWrapper.setPadding(20, 22, 20, 34)
rootScroll.addView(screenWrapper)

local mainFrameOuter, mainContainer = createFramedCard("#00E5FF", "#0A1224", 32, 6, 22, 26, 0)
screenWrapper.addView(mainFrameOuter)

local btnMargin = LinearLayout.LayoutParams(
  LinearLayout.LayoutParams.MATCH_PARENT,
  LinearLayout.LayoutParams.WRAP_CONTENT
)
btnMargin.setMargins(0, 0, 0, 14)

local rowParams = LinearLayout.LayoutParams(
  LinearLayout.LayoutParams.MATCH_PARENT,
  LinearLayout.LayoutParams.WRAP_CONTENT
)
rowParams.setMargins(0, 0, 0, 14)

local halfBtnParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
halfBtnParams.setMargins(6, 0, 6, 0)

-- TOP BRANDING HEADER CARD
local headerOuter, headerInner = createFramedCard("#FFD700", "#111E3B", 28, 6, 26, 30, 24)
headerInner.setGravity(Gravity.CENTER)

local tvTitle = TextView(activity)
tvTitle.setText(APP_TITLE)
tvTitle.setTextSize(23)
tvTitle.setTypeface(Typeface.DEFAULT_BOLD)
tvTitle.setTextColor(Color.parseColor("#FFFFFF"))
tvTitle.setGravity(Gravity.CENTER)
markAsHeading(tvTitle)
headerInner.addView(tvTitle)

headerInner.addView(makeDividerBar("#FFD700", 4, 8))

local tvDev = TextView(activity)
tvDev.setText(APP_DEV)
tvDev.setTextSize(17)
tvDev.setTypeface(Typeface.DEFAULT_BOLD)
tvDev.setTextColor(Color.parseColor("#FFD700"))
tvDev.setGravity(Gravity.CENTER)
markAsFocusableText(tvDev)
headerInner.addView(tvDev)

mainContainer.addView(headerOuter)

-- SECTION 1 CARD: Voice Sample & Favorite Voices
local sampleOuter, sampleBox = createFramedCard("#00E5FF", "#0E1B33", 26, 5, 22, 24, 24)

local tvSec1 = TextView(activity)
tvSec1.setText("1. Reference Human Voice Sample")
tvSec1.setTextSize(17)
tvSec1.setTypeface(Typeface.DEFAULT_BOLD)
tvSec1.setTextColor(Color.parseColor("#00E5FF"))
markAsHeading(tvSec1)
sampleBox.addView(tvSec1)
sampleBox.addView(makeDividerBar("#00E5FF", 3, 12))

tvSampleStatus = TextView(activity)
tvSampleStatus.setTextSize(14)
tvSampleStatus.setTypeface(Typeface.DEFAULT_BOLD)
tvSampleStatus.setPadding(18, 16, 18, 16)
tvSampleStatus.setBackground(makeBorderDrawable("#060D1A", "#0284C7", 18, 3))
tvSampleStatus.setLayoutParams(btnMargin)
markAsFocusableText(tvSampleStatus)
sampleBox.addView(tvSampleStatus)

local sampleRow = LinearLayout(activity)
sampleRow.setOrientation(LinearLayout.HORIZONTAL)
sampleRow.setLayoutParams(rowParams)

local btnSelectSample = Button(activity)
btnSelectSample.setText("SELECT VOICE FILE")
styleActionButton(btnSelectSample, "#0284C7", "#7DD3FC", "#FFFFFF", 18, 14, 20)
btnSelectSample.setLayoutParams(halfBtnParams)
sampleRow.addView(btnSelectSample)

local btnRecordSample = Button(activity)
btnRecordSample.setText("RECORD VOICE")
styleActionButton(btnRecordSample, "#DC2626", "#FCA5A5", "#FFFFFF", 18, 14, 20)
btnRecordSample.setLayoutParams(halfBtnParams)
sampleRow.addView(btnRecordSample)

sampleBox.addView(sampleRow)

local btnFavoriteVoices = Button(activity)
btnFavoriteVoices.setText("FAVORITE VOICES")
styleActionButton(btnFavoriteVoices, "#B45309", "#FDE047", "#FFFFFF", 18, 18, 18)
btnFavoriteVoices.setLayoutParams(btnMargin)
sampleBox.addView(btnFavoriteVoices)

sampleActionRow = LinearLayout(activity)
sampleActionRow.setOrientation(LinearLayout.HORIZONTAL)

btnPlaySample = Button(activity)
btnPlaySample.setText("PLAY SAMPLE")
styleActionButton(btnPlaySample, "#1E293B", "#38BDF8", "#FFFFFF", 18, 14, 18)
btnPlaySample.setLayoutParams(halfBtnParams)
sampleActionRow.addView(btnPlaySample)

btnAddFavorite = Button(activity)
btnAddFavorite.setText("ADD TO FAVORITES")
styleActionButton(btnAddFavorite, "#7C3AED", "#DDD6FE", "#FFFFFF", 18, 14, 18)
btnAddFavorite.setLayoutParams(halfBtnParams)
sampleActionRow.addView(btnAddFavorite)

sampleBox.addView(sampleActionRow)

local function updateSampleUI()
  if state.refAudioPath ~= "" and File(state.refAudioPath).exists() then
    local label = (state.refDisplayName ~= "" and state.refDisplayName) or File(state.refAudioPath).getName()
    tvSampleStatus.setText("Attached Sample: " .. label)
    tvSampleStatus.setTextColor(Color.parseColor("#4ADE80"))
    sampleActionRow.setVisibility(View.VISIBLE)
  else
    tvSampleStatus.setText("No Voice Sample Attached.")
    tvSampleStatus.setTextColor(Color.parseColor("#FBBF24"))
    sampleActionRow.setVisibility(View.GONE)
  end
end
updateSampleUI()

mainContainer.addView(sampleOuter)

-- SECTION 2 CARD: Voice Settings (Language, Emotion, Voice Speed)
local settingsOuter, settingsBox = createFramedCard("#D500F9", "#15112E", 26, 5, 22, 24, 24)

local tvSec2 = TextView(activity)
tvSec2.setText("2. Voice Cloning Settings")
tvSec2.setTextSize(17)
tvSec2.setTypeface(Typeface.DEFAULT_BOLD)
tvSec2.setTextColor(Color.parseColor("#E040FB"))
markAsHeading(tvSec2)
settingsBox.addView(tvSec2)
settingsBox.addView(makeDividerBar("#D500F9", 3, 14))

local btnLanguage = Button(activity)
styleActionButton(btnLanguage, "#0A071B", "#D500F9", "#FFFFFF", 18, 18, 18)
btnLanguage.setLayoutParams(btnMargin)
settingsBox.addView(btnLanguage)

local btnEmotion = Button(activity)
styleActionButton(btnEmotion, "#0A071B", "#FFD700", "#FFFFFF", 18, 18, 18)
btnEmotion.setLayoutParams(btnMargin)
settingsBox.addView(btnEmotion)

local btnSpeed = Button(activity)
styleActionButton(btnSpeed, "#0A071B", "#00E5FF", "#FFFFFF", 18, 18, 18)
settingsBox.addView(btnSpeed)

local function updateSettingsUI()
  local lang = LANGUAGES[state.langIndex] or LANGUAGES[1]
  local emo = EMOTIONS[state.emotionIndex] or EMOTIONS[1]
  local spd = SPEEDS[state.speedIndex] or SPEEDS[3]
  btnLanguage.setText("Language: " .. lang.name)
  btnEmotion.setText("Emotion: " .. emo.name)
  btnSpeed.setText("Voice Speed: " .. spd.name)
end
updateSettingsUI()

mainContainer.addView(settingsOuter)

-- SECTION 3 CARD: Script Input & Generate (No Premature "Ready" Label!)
local scriptOuter, scriptBox = createFramedCard("#00E676", "#0D211D", 26, 5, 22, 24, 24)

local tvSec3 = TextView(activity)
tvSec3.setText("3. Script Text (Urdu / English)")
tvSec3.setTextSize(17)
tvSec3.setTypeface(Typeface.DEFAULT_BOLD)
tvSec3.setTextColor(Color.parseColor("#00E676"))
markAsHeading(tvSec3)
scriptBox.addView(tvSec3)
scriptBox.addView(makeDividerBar("#00E676", 3, 12))

local etScript = EditText(activity)
etScript.setHint("Enter or paste Urdu or English text here...")
etScript.setHintTextColor(Color.parseColor("#64748B"))
etScript.setTextColor(Color.parseColor("#FFFFFF"))
etScript.setTextSize(16)
etScript.setMinLines(4)
etScript.setMaxLines(8)
etScript.setGravity(Gravity.TOP or Gravity.START)
etScript.setPadding(22, 20, 22, 20)
etScript.setBackground(makeBorderDrawable("#05110E", "#10B981", 20, 4))
etScript.setText("")
etScript.setLayoutParams(btnMargin)
scriptBox.addView(etScript)

local btnGenerate = Button(activity)
btnGenerate.setText("GENERATE CLONED VOICE")
btnGenerate.setTextSize(17)
styleActionButton(btnGenerate, "#059669", "#6EE7B7", "#FFFFFF", 22, 20, 24)
scriptBox.addView(btnGenerate)

progressBar = ProgressBar(activity, nil, android.R.attr.progressBarStyleHorizontal)
progressBar.setMax(100)
progressBar.setProgress(0)
progressBar.setVisibility(View.GONE)
local progParams = LinearLayout.LayoutParams(
  LinearLayout.LayoutParams.MATCH_PARENT,
  LinearLayout.LayoutParams.WRAP_CONTENT
)
progParams.setMargins(0, 16, 0, 6)
progressBar.setLayoutParams(progParams)
scriptBox.addView(progressBar)

tvProgressStatus = TextView(activity)
tvProgressStatus.setText("")
tvProgressStatus.setTextSize(14)
tvProgressStatus.setTypeface(Typeface.DEFAULT_BOLD)
tvProgressStatus.setTextColor(Color.parseColor("#A7F3D0"))
tvProgressStatus.setPadding(6, 10, 6, 0)
tvProgressStatus.setVisibility(View.GONE)
scriptBox.addView(tvProgressStatus)

mainContainer.addView(scriptOuter)

-- SECTION 4 CARD: Generated Audio Controls (HIDDEN UNTIL AUDIO IS GENERATED)
local outBoxInner
outputControlsOuter, outBoxInner = createFramedCard("#FFB300", "#1F1608", 26, 6, 22, 24, 24)
outputControlsOuter.setVisibility(View.GONE)

tvOutputStatus = TextView(activity)
tvOutputStatus.setText("")
tvOutputStatus.setTextSize(16)
tvOutputStatus.setTypeface(Typeface.DEFAULT_BOLD)
tvOutputStatus.setTextColor(Color.parseColor("#FFD700"))
tvOutputStatus.setPadding(4, 0, 4, 14)
markAsHeading(tvOutputStatus)
outBoxInner.addView(tvOutputStatus)

local outBtnRow = LinearLayout(activity)
outBtnRow.setOrientation(LinearLayout.HORIZONTAL)

btnPlayPauseOutput = Button(activity)
btnPlayPauseOutput.setText("PLAY")
styleActionButton(btnPlayPauseOutput, "#1D4ED8", "#60A5FA", "#FFFFFF", 18, 12, 20)
btnPlayPauseOutput.setLayoutParams(halfBtnParams)
outBtnRow.addView(btnPlayPauseOutput)

btnDownloadOutput = Button(activity)
btnDownloadOutput.setText("DOWNLOAD")
styleActionButton(btnDownloadOutput, "#059669", "#34D399", "#FFFFFF", 18, 12, 20)
btnDownloadOutput.setLayoutParams(halfBtnParams)
outBtnRow.addView(btnDownloadOutput)

btnRenameOutput = Button(activity)
btnRenameOutput.setText("RENAME")
styleActionButton(btnRenameOutput, "#7C3AED", "#C4B5FD", "#FFFFFF", 18, 12, 20)
btnRenameOutput.setLayoutParams(halfBtnParams)
outBtnRow.addView(btnRenameOutput)

outBoxInner.addView(outBtnRow)
mainContainer.addView(outputControlsOuter)

-- SECTION 5 FOOTER: ABOUT & EXIT BUTTONS
local footerOuter, footerInner = createFramedCard("#38BDF8", "#0E172A", 24, 4, 16, 16, 0)
local footerRow = LinearLayout(activity)
footerRow.setOrientation(LinearLayout.HORIZONTAL)

local btnAbout = Button(activity)
btnAbout.setText("ABOUT")
btnAbout.setTextSize(15)
styleActionButton(btnAbout, "#1E3A8A", "#60A5FA", "#FFFFFF", 18, 16, 20)
btnAbout.setLayoutParams(halfBtnParams)
footerRow.addView(btnAbout)

local btnExit = Button(activity)
btnExit.setText("EXIT")
btnExit.setTextSize(15)
styleActionButton(btnExit, "#991B1B", "#F87171", "#FFFFFF", 18, 16, 20)
btnExit.setLayoutParams(halfBtnParams)
footerRow.addView(btnExit)

footerInner.addView(footerRow)
mainContainer.addView(footerOuter)

activity.setContentView(rootScroll)

-- ============================================================================
-- Custom Styled Selector Window (Scrollable for Language, 20 Emotions & Speed)
-- ============================================================================
local function showStyledSelectorWindow(windowTitle, optionsList, selectedIdx, onSelectCallback)
  local wrapOuter, dlgBox = createFramedCard("#E040FB", "#130924", 30, 6, 22, 22, 0)

  local headOuter, headInner = createFramedCard("#FFD700", "#2A0F4D", 22, 5, 18, 20, 16)
  headInner.setGravity(Gravity.CENTER)

  local tvHead = TextView(activity)
  tvHead.setText(windowTitle)
  tvHead.setTextSize(19)
  tvHead.setTypeface(Typeface.DEFAULT_BOLD)
  tvHead.setTextColor(Color.parseColor("#FFD700"))
  tvHead.setGravity(Gravity.CENTER)
  markAsHeading(tvHead)
  headInner.addView(tvHead)
  dlgBox.addView(headOuter)

  local listScroll = ScrollView(activity)
  local maxH = (#optionsList > 6) and 760 or WindowManager.LayoutParams.WRAP_CONTENT
  local scParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, maxH)
  scParams.setMargins(0, 0, 0, 14)
  listScroll.setLayoutParams(scParams)

  local itemsBox = LinearLayout(activity)
  itemsBox.setOrientation(LinearLayout.VERTICAL)
  listScroll.addView(itemsBox)
  dlgBox.addView(listScroll)

  local dlg = nil

  for idx, opt in ipairs(optionsList) do
    local isSel = (idx == selectedIdx)
    local btnOpt = Button(activity)
    btnOpt.setText(isSel and ("Selected: " .. opt.name) or opt.name)
    btnOpt.setTextSize(15)
    styleActionButton(
      btnOpt,
      isSel and "#3B0764" or "#1E1B4B",
      isSel and "#FFD700" or "#A855F7",
      isSel and "#FFD700" or "#FFFFFF",
      18, 20, 18
    )
    btnOpt.setLayoutParams(btnMargin)
    btnOpt.onClick = function()
      vibrate35ms()
      if dlg then dlg.dismiss() end
      onSelectCallback(idx)
    end
    itemsBox.addView(btnOpt)
  end

  local btnCancel = Button(activity)
  btnCancel.setText("CLOSE")
  styleActionButton(btnCancel, "#7F1D1D", "#F87171", "#FFFFFF", 18, 18, 18)
  btnCancel.onClick = function()
    vibrate35ms()
    if dlg then dlg.dismiss() end
  end
  dlgBox.addView(btnCancel)

  dlg = showRichDialog(wrapOuter, "#E040FB", "#130924")
end

-- ============================================================================
-- Save to Favorites Dialog & Favorite Voices Manager Window
-- ============================================================================
local function showAddToFavoritesDialog()
  if state.refAudioPath == "" or not File(state.refAudioPath).exists() then
    speakText("Please select or record a voice sample first.")
    return
  end

  local wrapOuter, dlgBox = createFramedCard("#FFD700", "#1E1208", 30, 6, 24, 24, 0)

  local headOuter, headInner = createFramedCard("#00E5FF", "#3B2006", 22, 4, 18, 20, 16)
  headInner.setGravity(Gravity.CENTER)

  local tvHead = TextView(activity)
  tvHead.setText("Save Voice to Favorites")
  tvHead.setTextSize(19)
  tvHead.setTypeface(Typeface.DEFAULT_BOLD)
  tvHead.setTextColor(Color.parseColor("#FFD700"))
  tvHead.setGravity(Gravity.CENTER)
  markAsHeading(tvHead)
  headInner.addView(tvHead)
  dlgBox.addView(headOuter)

  local defaultName = (state.refDisplayName ~= "" and state.refDisplayName:gsub("%.[^%.]+$", "")) or ("Voice_" .. os.date("%H%M%S"))
  local etFavName = EditText(activity)
  etFavName.setHint("Enter favorite voice name...")
  etFavName.setHintTextColor(Color.parseColor("#A8A29E"))
  etFavName.setTextColor(Color.parseColor("#FFFFFF"))
  etFavName.setTextSize(16)
  etFavName.setSingleLine(true)
  etFavName.setPadding(20, 18, 20, 18)
  etFavName.setBackground(makeBorderDrawable("#0D0802", "#FFD700", 18, 4))
  etFavName.setText(defaultName)
  etFavName.setLayoutParams(btnMargin)
  dlgBox.addView(etFavName)

  local actionRow = LinearLayout(activity)
  actionRow.setOrientation(LinearLayout.HORIZONTAL)

  local btnCancel = Button(activity)
  btnCancel.setText("CANCEL")
  styleActionButton(btnCancel, "#44403C", "#CBD5E1", "#FFFFFF", 18, 16, 18)
  btnCancel.setLayoutParams(halfBtnParams)
  actionRow.addView(btnCancel)

  local btnSaveFav = Button(activity)
  btnSaveFav.setText("SAVE FAVORITE")
  styleActionButton(btnSaveFav, "#059669", "#34D399", "#FFFFFF", 18, 16, 18)
  btnSaveFav.setLayoutParams(halfBtnParams)
  actionRow.addView(btnSaveFav)

  dlgBox.addView(actionRow)

  local dlg = showRichDialog(wrapOuter, "#FFD700", "#1E1208")

  btnCancel.onClick = function()
    vibrate35ms()
    dlg.dismiss()
  end

  btnSaveFav.onClick = function()
    vibrate35ms()
    local vName = tostring(etFavName.getText() or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("|", "_")
    if vName == "" then
      vName = "Favorite_Voice_" .. os.date("%H%M%S")
    end
    local ext = (state.refAudioPath:match("%.([^%.]+)$") or "m4a"):lower()
    local destFile = FAV_DIR .. "/fav_" .. tostring(os.time()) .. "_" .. tostring(math.random(100, 999)) .. "." .. ext

    local okCopy = pcall(function()
      local LuaUtil = luajava.bindClass("com.androlua.LuaUtil")
      local fis = FileInputStream(state.refAudioPath)
      local fos = FileOutputStream(destFile)
      LuaUtil.copyFile(fis, fos)
      fos.flush()
      fos.close()
      fis.close()
    end)

    if okCopy and File(destFile).exists() then
      local list = loadFavoritesList()
      table.insert(list, 1, { name = vName, path = destFile })
      saveFavoritesList(list)
      speakText("Saved to Favorite Voices: " .. vName)
      dlg.dismiss()
    else
      speakText("Failed to save favorite voice.")
    end
  end
end

local function showFavoriteVoicesWindow()
  stopSamplePlayback()
  stopOutputPlayback()
  stopBrowserPreview()

  local wrapOuter, dlgRoot = createFramedCard("#FFD700", "#1A0F2E", 30, 6, 22, 22, 0)

  local topOuter, topBanner = createFramedCard("#00E5FF", "#2D124D", 22, 4, 18, 20, 16)
  topBanner.setGravity(Gravity.CENTER)

  local tvFavTitle = TextView(activity)
  tvFavTitle.setText("Favorite Voice Samples")
  tvFavTitle.setTextSize(19)
  tvFavTitle.setTypeface(Typeface.DEFAULT_BOLD)
  tvFavTitle.setTextColor(Color.parseColor("#FFD700"))
  tvFavTitle.setGravity(Gravity.CENTER)
  markAsHeading(tvFavTitle)
  topBanner.addView(tvFavTitle)

  local tvFavCount = TextView(activity)
  tvFavCount.setTextSize(14)
  tvFavCount.setTypeface(Typeface.DEFAULT_BOLD)
  tvFavCount.setTextColor(Color.parseColor("#00E5FF"))
  tvFavCount.setGravity(Gravity.CENTER)
  tvFavCount.setPadding(0, 6, 0, 0)
  markAsFocusableText(tvFavCount)
  topBanner.addView(tvFavCount)

  dlgRoot.addView(topOuter)

  local listScroll = ScrollView(activity)
  local scParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 740)
  scParams.setMargins(0, 0, 0, 16)
  listScroll.setLayoutParams(scParams)
  listScroll.setBackground(makeBorderDrawable("#0D071A", "#A855F7", 20, 3))
  listScroll.setPadding(12, 12, 12, 12)

  local itemsContainer = LinearLayout(activity)
  itemsContainer.setOrientation(LinearLayout.VERTICAL)
  listScroll.addView(itemsContainer)
  dlgRoot.addView(listScroll)

  local btnCloseFav = Button(activity)
  btnCloseFav.setText("CLOSE")
  styleActionButton(btnCloseFav, "#DC2626", "#FCA5A5", "#FFFFFF", 18, 18, 18)
  dlgRoot.addView(btnCloseFav)

  local dlg = showRichDialog(wrapOuter, "#FFD700", "#1A0F2E")

  dlg.setOnDismissListener(DialogInterface.OnDismissListener{
    onDismiss = function()
      stopBrowserPreview()
    end
  })

  local renderFavorites
  renderFavorites = function()
    stopBrowserPreview()
    itemsContainer.removeAllViews()
    local favs = loadFavoritesList()
    tvFavCount.setText("Saved Favorites: " .. tostring(#favs))

    if #favs == 0 then
      local tvEmpty = TextView(activity)
      tvEmpty.setText("No favorite voices saved yet.\nSelect or record a voice sample first, then tap 'ADD TO FAVORITES'.")
      tvEmpty.setTextSize(15)
      tvEmpty.setTextColor(Color.parseColor("#FBBF24"))
      tvEmpty.setGravity(Gravity.CENTER)
      tvEmpty.setPadding(20, 40, 20, 40)
      markAsFocusableText(tvEmpty)
      itemsContainer.addView(tvEmpty)
      return
    end

    for idx, item in ipairs(favs) do
      local fPath = item.path
      local fName = item.name

      local itemRow = LinearLayout(activity)
      itemRow.setOrientation(LinearLayout.HORIZONTAL)
      itemRow.setGravity(Gravity.CENTER_VERTICAL)
      itemRow.setPadding(10, 10, 10, 10)
      itemRow.setBackground(makeBorderDrawable("#24123D", "#FFD700", 18, 3))
      itemRow.setLayoutParams(btnMargin)

      local nameParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
      nameParams.setMargins(0, 0, 8, 0)

      local btnSelectFav = Button(activity)
      btnSelectFav.setText(fName)
      btnSelectFav.setTextSize(14)
      btnSelectFav.setGravity(Gravity.START or Gravity.CENTER_VERTICAL)
      styleActionButton(btnSelectFav, "#120824", "#00E5FF", "#FFFFFF", 14, 16, 16)
      btnSelectFav.setLayoutParams(nameParams)

      local sideMargin = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
      sideMargin.setMargins(0, 0, 8, 0)

      local btnPlayToggle = Button(activity)
      btnPlayToggle.setText("Play")
      btnPlayToggle.setTextSize(13)
      styleActionButton(btnPlayToggle, "#059669", "#34D399", "#FFFFFF", 14, 20, 14)
      btnPlayToggle.setLayoutParams(sideMargin)

      local btnDelFav = Button(activity)
      btnDelFav.setText("Delete")
      btnDelFav.setTextSize(13)
      styleActionButton(btnDelFav, "#991B1B", "#F87171", "#FFFFFF", 14, 18, 14)

      btnSelectFav.onClick = function()
        vibrate35ms()
        stopBrowserPreview()
        state.refAudioPath = fPath
        state.refDisplayName = fName
        updateSampleUI()
        speakText("Selected Favorite Voice: " .. fName)
        dlg.dismiss()
      end

      btnPlayToggle.onClick = function()
        vibrate35ms()
        if state.browserPreviewPath == fPath and state.browserPreviewPlayer then
          if state.browserPreviewPaused then
            local okResume = pcall(function()
              state.browserPreviewPlayer.start()
              state.browserPreviewPaused = false
              btnPlayToggle.setText("Pause")
              styleActionButton(btnPlayToggle, "#D97706", "#FDE047", "#FFFFFF", 14, 20, 14)
            end)
            if okResume then return end
          else
            local okPause = pcall(function()
              state.browserPreviewPlayer.pause()
              state.browserPreviewPaused = true
              btnPlayToggle.setText("Play")
              styleActionButton(btnPlayToggle, "#059669", "#34D399", "#FFFFFF", 14, 20, 14)
            end)
            if okPause then return end
          end
        end

        stopBrowserPreview()
        pcall(function()
          local mp = MediaPlayer()
          mp.setDataSource(fPath)
          mp.prepare()
          mp.start()
          state.browserPreviewPlayer = mp
          state.browserPreviewPath = fPath
          state.browserPreviewPaused = false
          state.activePreviewBtn = btnPlayToggle
          btnPlayToggle.setText("Pause")
          styleActionButton(btnPlayToggle, "#D97706", "#FDE047", "#FFFFFF", 14, 20, 14)
          mp.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion = function()
              stopBrowserPreview()
            end
          })
        end)
      end

      btnDelFav.onClick = function()
        vibrate35ms()
        stopBrowserPreview()
        pcall(function() File(fPath).delete() end)
        table.remove(favs, idx)
        saveFavoritesList(favs)
        speakText("Removed from favorites: " .. fName)
        renderFavorites()
      end

      itemRow.addView(btnSelectFav)
      itemRow.addView(btnPlayToggle)
      itemRow.addView(btnDelFav)
      itemsContainer.addView(itemRow)
    end
  end

  btnCloseFav.onClick = function()
    vibrate35ms()
    stopBrowserPreview()
    dlg.dismiss()
  end

  renderFavorites()
end

-- ============================================================================
-- Custom Styled Rename Window (Warm Amber & Gold Theme)
-- ============================================================================
local function showRenameDialog()
  local wrapOuter, dlgBox = createFramedCard("#FFB300", "#1C1206", 30, 6, 24, 24, 0)

  local headOuter, headInner = createFramedCard("#FFD700", "#3D2206", 22, 4, 18, 20, 18)
  headInner.setGravity(Gravity.CENTER)

  local tvHead = TextView(activity)
  tvHead.setText("Rename Cloned Audio")
  tvHead.setTextSize(19)
  tvHead.setTypeface(Typeface.DEFAULT_BOLD)
  tvHead.setTextColor(Color.parseColor("#FFD700"))
  tvHead.setGravity(Gravity.CENTER)
  markAsHeading(tvHead)
  headInner.addView(tvHead)
  dlgBox.addView(headOuter)

  local etName = EditText(activity)
  etName.setHint("Enter custom file name...")
  etName.setHintTextColor(Color.parseColor("#A8A29E"))
  etName.setTextColor(Color.parseColor("#FFFFFF"))
  etName.setTextSize(16)
  etName.setSingleLine(true)
  etName.setPadding(22, 20, 22, 20)
  etName.setBackground(makeBorderDrawable("#0D0802", "#FFB300", 18, 4))
  etName.setText(state.customFileName or "")
  etName.setLayoutParams(btnMargin)
  dlgBox.addView(etName)

  local actionRow = LinearLayout(activity)
  actionRow.setOrientation(LinearLayout.HORIZONTAL)

  local btnCancel = Button(activity)
  btnCancel.setText("CANCEL")
  styleActionButton(btnCancel, "#44403C", "#CBD5E1", "#FFFFFF", 18, 16, 20)
  btnCancel.setLayoutParams(halfBtnParams)
  actionRow.addView(btnCancel)

  local btnOk = Button(activity)
  btnOk.setText("OK")
  styleActionButton(btnOk, "#D97706", "#FDE047", "#FFFFFF", 18, 16, 20)
  btnOk.setLayoutParams(halfBtnParams)
  actionRow.addView(btnOk)

  dlgBox.addView(actionRow)

  local dlg = showRichDialog(wrapOuter, "#FFB300", "#1C1206")

  btnCancel.onClick = function()
    vibrate35ms()
    dlg.dismiss()
  end

  btnOk.onClick = function()
    vibrate35ms()
    local entered = tostring(etName.getText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    entered = entered:gsub("[\\/:%*%?\"<>|]", "_")
    entered = entered:gsub("%.wav$", ""):gsub("%.mp3$", "")
    if entered == "" then
      entered = "Cloned_Voice_" .. os.date("%Y%m%d_%H%M%S")
    end
    state.customFileName = entered
    tvOutputStatus.setText("Audio Name: " .. entered .. ".wav")
    speakText("Renamed to " .. entered)
    dlg.dismiss()
  end
end

-- ============================================================================
-- ABOUT WINDOW (True Screen-Reader Headings + Separate Focusable Cards)
-- ============================================================================
local function showAboutWindow()
  local wrapOuter, dlgRoot = createFramedCard("#FFD700", "#11061D", 30, 6, 20, 22, 0)

  local topOuter, topBanner = createFramedCard("#FF4081", "#280940", 24, 5, 22, 24, 16)
  topBanner.setGravity(Gravity.CENTER)

  local tvAbTitle = TextView(activity)
  tvAbTitle.setText(APP_TITLE)
  tvAbTitle.setTextSize(22)
  tvAbTitle.setTypeface(Typeface.DEFAULT_BOLD)
  tvAbTitle.setTextColor(Color.parseColor("#FFFFFF"))
  tvAbTitle.setGravity(Gravity.CENTER)
  markAsHeading(tvAbTitle)
  topBanner.addView(tvAbTitle)

  topBanner.addView(makeDividerBar("#FFD700", 4, 8))

  local tvAbDev = TextView(activity)
  tvAbDev.setText(APP_DEV)
  tvAbDev.setTextSize(17)
  tvAbDev.setTypeface(Typeface.DEFAULT_BOLD)
  tvAbDev.setTextColor(Color.parseColor("#FFD700"))
  tvAbDev.setGravity(Gravity.CENTER)
  markAsFocusableText(tvAbDev)
  topBanner.addView(tvAbDev)

  dlgRoot.addView(topOuter)

  local bodyScroll = ScrollView(activity)
  local scrollParams = LinearLayout.LayoutParams(
    LinearLayout.LayoutParams.MATCH_PARENT,
    760
  )
  scrollParams.setMargins(0, 0, 0, 14)
  bodyScroll.setLayoutParams(scrollParams)
  bodyScroll.setBackground(makeBorderDrawable("#080310", "#A855F7", 22, 3))
  bodyScroll.setPadding(12, 12, 12, 12)

  local bodyLayout = LinearLayout(activity)
  bodyLayout.setOrientation(LinearLayout.VERTICAL)
  bodyScroll.addView(bodyLayout)

  local function addAboutHeadingAndItems(headingText, itemsList, headingBorderHex, headingBgHex, headingTextHex, itemBgHex, itemBorderHex)
    local hCard = LinearLayout(activity)
    hCard.setOrientation(LinearLayout.VERTICAL)
    hCard.setPadding(20, 16, 20, 16)
    hCard.setBackgroundColor(Color.parseColor(headingBgHex))
    hCard.setBackground(makeBorderDrawable(headingBgHex, headingBorderHex, 20, 5))
    local hlp = LinearLayout.LayoutParams(
      LinearLayout.LayoutParams.MATCH_PARENT,
      LinearLayout.LayoutParams.WRAP_CONTENT
    )
    hlp.setMargins(0, 6, 0, 10)
    hCard.setLayoutParams(hlp)

    local tvH = TextView(activity)
    tvH.setText(headingText)
    tvH.setTextSize(18)
    tvH.setTypeface(Typeface.DEFAULT_BOLD)
    tvH.setTextColor(Color.parseColor(headingTextHex))
    markAsHeading(tvH)
    hCard.addView(tvH)

    bodyLayout.addView(hCard)

    for _, itemTxt in ipairs(itemsList) do
      local itemCard = LinearLayout(activity)
      itemCard.setOrientation(LinearLayout.VERTICAL)
      itemCard.setPadding(20, 16, 20, 16)
      itemCard.setBackgroundColor(Color.parseColor(itemBgHex))
      itemCard.setBackground(makeBorderDrawable(itemBgHex, itemBorderHex, 18, 3))
      local ilp = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
      )
      ilp.setMargins(0, 0, 0, 12)
      itemCard.setLayoutParams(ilp)

      local tvItem = TextView(activity)
      tvItem.setText(itemTxt)
      tvItem.setTextSize(15)
      tvItem.setTextColor(Color.parseColor("#F8FAFC"))
      markAsFocusableText(tvItem)
      itemCard.addView(tvItem)

      bodyLayout.addView(itemCard)
    end
  end

  addAboutHeadingAndItems(
    "Tool Overview",
    {
      "AI Voice Cloner Studio is a neural human voice cloning tool that captures the natural tone, pitch, and vocal identity of any human voice sample and generates realistic speech in Urdu, English, Hindi, Arabic, and Punjabi."
    },
    "#00E5FF", "#0A2540", "#00E5FF", "#061526", "#38BDF8"
  )

  addAboutHeadingAndItems(
    "Key Features",
    {
      "Human Voice Cloning: Converts your written text into natural speech matching your selected or recorded human voice sample.",
      "Favorite Voices: Save your favorite voice samples inside the tool for instant selection anytime without searching again.",
      "20 Voice Emotions: Customize the speaking style with 20 emotions including Natural, Happy, Sad, Storytelling, Dramatic, Suspense, Whisper, News Anchor, and Poetry.",
      "Multi-Language & Speed Control: Supports Urdu, English, Hindi, Arabic, and Punjabi with adjustable speaking speeds from 0.85x to 1.20x.",
      "In-App Audio Search & Preview: Search all phone audio files by name and listen to them with Play and Pause buttons before selecting.",
      "Custom Rename & Download: Preview your generated voice, rename the audio file to any custom name, and download it directly to your Download folder."
    },
    "#00E676", "#082E22", "#00E676", "#051B14", "#10B981"
  )

  addAboutHeadingAndItems(
    "How to Use",
    {
      "Step 1 (Select or Record Voice): Tap 'SELECT VOICE FILE' to choose an audio from your phone, tap 'RECORD VOICE' to record your own voice, or tap 'FAVORITE VOICES' to pick a saved voice.",
      "Step 2 (Save to Favorites): Once a voice sample is attached, tap 'ADD TO FAVORITES' if you want to save that voice with a custom name for future use.",
      "Step 3 (Configure Settings): Choose your target Language, select a Voice Emotion, and adjust the Voice Speed.",
      "Step 4 (Enter Text & Generate): Paste or type your Urdu or English script into the Script Text box and tap 'GENERATE CLONED VOICE'.",
      "Step 5 (Play, Rename & Download): When the cloned audio is ready, tap 'PLAY' or 'PAUSE' to listen, tap 'RENAME' to change the file name, and tap 'DOWNLOAD' to save it."
    },
    "#E040FB", "#2A0E42", "#E040FB", "#170726", "#C084FC"
  )

  addAboutHeadingAndItems(
    "Best Quality Tips",
    {
      "Use a clear 5 to 12 second voice sample without background music or noise for the most accurate voice cloning result.",
      "Use proper punctuation such as full stops and commas in long Urdu and English paragraphs for natural pauses."
    },
    "#FFB300", "#332006", "#FFD700", "#1C1103", "#F59E0B"
  )

  dlgRoot.addView(bodyScroll)

  local btnFeedback = Button(activity)
  btnFeedback.setText("SEND FEEDBACK")
  btnFeedback.setTextSize(15)
  styleActionButton(btnFeedback, "#059669", "#6EE7B7", "#FFFFFF", 18, 18, 18)
  btnFeedback.setLayoutParams(btnMargin)
  dlgRoot.addView(btnFeedback)

  local btnCloseAbout = Button(activity)
  btnCloseAbout.setText("CLOSE")
  btnCloseAbout.setTextSize(15)
  styleActionButton(btnCloseAbout, "#DC2626", "#FCA5A5", "#FFFFFF", 18, 18, 18)
  dlgRoot.addView(btnCloseAbout)

  local dlg = showRichDialog(wrapOuter, "#FFD700", "#11061D")

  btnFeedback.onClick = function()
    vibrate35ms()
    pcall(function()
      local msg = "السلام علیکم عبدالرحمن بھائی! میں AI Voice Cloner Studio ٹول استعمال کر رہا ہوں اور میرا فیڈ بیک یہ ہے: "
      local encoded = URLEncoder.encode(msg, "UTF-8")
      local url = "https://wa.me/" .. FEEDBACK_PHONE .. "?text=" .. encoded
      local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
      activity.startActivity(intent)
    end)
  end

  btnCloseAbout.onClick = function()
    vibrate35ms()
    dlg.dismiss()
  end
end

-- ============================================================================
-- Styled In-Tool Audio Picker Window (Ocean Emerald Theme + Live Search)
-- ============================================================================
local AUDIO_EXTENSIONS = {
  wav = true, mp3 = true, m4a = true, aac = true, ogg = true, flac = true, opus = true
}

local function isAudioFile(name)
  local ext = tostring(name or ""):match("%.([^%.]+)$")
  if not ext then return false end
  return AUDIO_EXTENSIONS[ext:lower()] == true
end

local function scanAllPhoneAudios()
  local list = {}
  local seenPaths = {}

  local function addFileIfValid(pathStr, modTimeHint)
    if not pathStr or pathStr == "" or seenPaths[pathStr] then return end
    if pathStr:find(WORK_DIR, 1, true) then return end
    local ok, f = pcall(function() return File(pathStr) end)
    if not ok or not f then return end
    local existsOk, ex = pcall(function() return f.exists() and f.isFile() end)
    if not existsOk or not ex then return end
    local name = tostring(f.getName() or "")
    if not isAudioFile(name) then return end
    local lenOk, lenVal = pcall(function() return f.length() end)
    local sizeBytes = (lenOk and tonumber(lenVal)) or 0
    if sizeBytes < 512 then return end
    local modOk, modVal = pcall(function() return f.lastModified() end)
    local mTime = (modOk and tonumber(modVal)) or tonumber(modTimeHint) or 0

    seenPaths[pathStr] = true
    table.insert(list, {
      path = pathStr,
      name = name,
      mtime = mTime
    })
  end

  pcall(function()
    local resolver = activity.getContentResolver()
    local uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
    local cursor = resolver.query(uri, nil, nil, nil, nil)
    if cursor then
      local dataIdx = cursor.getColumnIndex("_data")
      local dateIdx = cursor.getColumnIndex("date_modified")
      if dataIdx and dataIdx >= 0 then
        while cursor.moveToNext() do
          local p = cursor.getString(dataIdx)
          local dt = (dateIdx and dateIdx >= 0) and (tonumber(cursor.getLong(dateIdx)) or 0) * 1000 or 0
          addFileIfValid(p, dt)
        end
      end
      cursor.close()
    end
  end)

  local function scanFolder(dirPath, depth)
    if depth > 2 then return end
    pcall(function()
      local d = File(dirPath)
      if not d.exists() or not d.isDirectory() then return end
      local raw = d.listFiles()
      if not raw then return end
      local arr = luajava.astable(raw)
      for _, item in ipairs(arr) do
        local nm = tostring(item.getName() or "")
        if not nm:match("^%.") then
          if item.isDirectory() then
            scanFolder(item.getAbsolutePath(), depth + 1)
          else
            addFileIfValid(item.getAbsolutePath(), 0)
          end
        end
      end
    end)
  end

  scanFolder("/storage/emulated/0/Download", 1)
  scanFolder("/storage/emulated/0/Music", 1)
  scanFolder("/storage/emulated/0/Recordings", 1)
  scanFolder("/storage/emulated/0/Sounds", 1)

  table.sort(list, function(a, b)
    return (tonumber(a.mtime) or 0) > (tonumber(b.mtime) or 0)
  end)

  return list
end

local function showInToolAudioPicker()
  stopSamplePlayback()
  stopOutputPlayback()
  stopBrowserPreview()

  local allAudios = scanAllPhoneAudios()
  local totalCount = #allAudios

  local wrapOuter, dlgRoot = createFramedCard("#00F5D4", "#04181F", 30, 6, 20, 22, 0)

  local topOuter, topBanner = createFramedCard("#FFD700", "#083344", 22, 4, 18, 18, 14)
  topBanner.setGravity(Gravity.CENTER)

  local tvTotalCounter = TextView(activity)
  tvTotalCounter.setText("Total Audios: " .. tostring(totalCount))
  tvTotalCounter.setTextSize(18)
  tvTotalCounter.setTypeface(Typeface.DEFAULT_BOLD)
  tvTotalCounter.setTextColor(Color.parseColor("#FFD700"))
  tvTotalCounter.setGravity(Gravity.CENTER)
  markAsHeading(tvTotalCounter)
  topBanner.addView(tvTotalCounter)

  dlgRoot.addView(topOuter)

  local etSearch = EditText(activity)
  etSearch.setHint("Search audio name...")
  etSearch.setHintTextColor(Color.parseColor("#64748B"))
  etSearch.setTextColor(Color.parseColor("#FFFFFF"))
  etSearch.setTextSize(15)
  etSearch.setSingleLine(true)
  etSearch.setImeOptions(EditorInfo.IME_ACTION_SEARCH)
  etSearch.setPadding(22, 18, 22, 18)
  etSearch.setBackground(makeBorderDrawable("#020D12", "#00F5D4", 18, 4))
  etSearch.setLayoutParams(btnMargin)
  dlgRoot.addView(etSearch)

  local listScroll = ScrollView(activity)
  local scrollParams = LinearLayout.LayoutParams(
    LinearLayout.LayoutParams.MATCH_PARENT,
    760
  )
  scrollParams.setMargins(0, 0, 0, 14)
  listScroll.setLayoutParams(scrollParams)
  listScroll.setBackground(makeBorderDrawable("#020D12", "#0E7490", 22, 3))
  listScroll.setPadding(12, 12, 12, 12)

  local itemsContainer = LinearLayout(activity)
  itemsContainer.setOrientation(LinearLayout.VERTICAL)
  listScroll.addView(itemsContainer)
  dlgRoot.addView(listScroll)

  local btnClosePicker = Button(activity)
  btnClosePicker.setText("CLOSE")
  btnClosePicker.setTextSize(15)
  styleActionButton(btnClosePicker, "#DC2626", "#FCA5A5", "#FFFFFF", 18, 18, 18)
  dlgRoot.addView(btnClosePicker)

  local dlg = showRichDialog(wrapOuter, "#00F5D4", "#04181F")

  dlg.setOnDismissListener(DialogInterface.OnDismissListener{
    onDismiss = function()
      stopBrowserPreview()
    end
  })

  local function renderFilteredAudios(queryStr)
    stopBrowserPreview()
    itemsContainer.removeAllViews()

    local q = tostring(queryStr or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local matched = {}

    for _, item in ipairs(allAudios) do
      if q == "" or item.name:lower():find(q, 1, true) then
        table.insert(matched, item)
      end
    end

    if q == "" then
      tvTotalCounter.setText("Total Audios: " .. tostring(totalCount))
    else
      tvTotalCounter.setText("Audios Found: " .. tostring(#matched))
    end

    if #matched == 0 then
      local tvEmpty = TextView(activity)
      tvEmpty.setText("No audio found.")
      tvEmpty.setTextSize(15)
      tvEmpty.setTextColor(Color.parseColor("#F87171"))
      tvEmpty.setGravity(Gravity.CENTER)
      tvEmpty.setPadding(20, 36, 20, 36)
      markAsFocusableText(tvEmpty)
      itemsContainer.addView(tvEmpty)
      return
    end

    local maxShow = math.min(#matched, 180)
    for i = 1, maxShow do
      local item = matched[i]
      local fPath = item.path
      local fName = item.name

      local itemRow = LinearLayout(activity)
      itemRow.setOrientation(LinearLayout.HORIZONTAL)
      itemRow.setGravity(Gravity.CENTER_VERTICAL)
      itemRow.setPadding(10, 10, 10, 10)
      itemRow.setBackground(makeBorderDrawable("#082836", "#00E5FF", 18, 3))
      itemRow.setLayoutParams(btnMargin)

      local nameParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
      nameParams.setMargins(0, 0, 10, 0)

      local btnAudioName = Button(activity)
      btnAudioName.setText(fName)
      btnAudioName.setTextSize(14)
      btnAudioName.setGravity(Gravity.START or Gravity.CENTER_VERTICAL)
      styleActionButton(btnAudioName, "#04131A", "#38BDF8", "#FFFFFF", 14, 16, 14)
      btnAudioName.setLayoutParams(nameParams)

      local btnPlayToggle = Button(activity)
      btnPlayToggle.setText("Play")
      btnPlayToggle.setTextSize(14)
      styleActionButton(btnPlayToggle, "#059669", "#34D399", "#FFFFFF", 16, 22, 14)

      btnAudioName.onClick = function()
        vibrate35ms()
        stopBrowserPreview()
        state.refAudioPath = fPath
        state.refDisplayName = fName
        updateSampleUI()
        speakText("Selected: " .. fName)
        dlg.dismiss()
      end

      btnPlayToggle.onClick = function()
        vibrate35ms()
        if state.browserPreviewPath == fPath and state.browserPreviewPlayer then
          if state.browserPreviewPaused then
            local okResume = pcall(function()
              state.browserPreviewPlayer.start()
              state.browserPreviewPaused = false
              btnPlayToggle.setText("Pause")
              styleActionButton(btnPlayToggle, "#D97706", "#FDE047", "#FFFFFF", 16, 22, 14)
            end)
            if okResume then return end
          else
            local okPause = pcall(function()
              state.browserPreviewPlayer.pause()
              state.browserPreviewPaused = true
              btnPlayToggle.setText("Play")
              styleActionButton(btnPlayToggle, "#059669", "#34D399", "#FFFFFF", 16, 22, 14)
            end)
            if okPause then return end
          end
        end

        stopBrowserPreview()
        local okStart = pcall(function()
          local mp = MediaPlayer()
          mp.setDataSource(fPath)
          mp.prepare()
          mp.start()
          state.browserPreviewPlayer = mp
          state.browserPreviewPath = fPath
          state.browserPreviewPaused = false
          state.activePreviewBtn = btnPlayToggle
          btnPlayToggle.setText("Pause")
          styleActionButton(btnPlayToggle, "#D97706", "#FDE047", "#FFFFFF", 16, 22, 14)

          mp.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion = function()
              stopBrowserPreview()
            end
          })
        end)

        if not okStart then
          stopBrowserPreview()
          speakText("Cannot play this audio.")
        end
      end

      itemRow.addView(btnAudioName)
      itemRow.addView(btnPlayToggle)
      itemsContainer.addView(itemRow)
    end
  end

  etSearch.addTextChangedListener(TextWatcher{
    beforeTextChanged = function() end,
    onTextChanged = function(s)
      renderFilteredAudios(tostring(s or ""))
    end,
    afterTextChanged = function() end
  })

  etSearch.setOnEditorActionListener(TextView.OnEditorActionListener{
    onEditorAction = function(v, actionId, event)
      if actionId == EditorInfo.IME_ACTION_SEARCH or actionId == EditorInfo.IME_ACTION_DONE then
        vibrate35ms()
        renderFilteredAudios(tostring(etSearch.getText() or ""))
        pcall(function()
          local imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
          imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
        end)
        return true
      end
      return false
    end
  })

  btnClosePicker.onClick = function()
    vibrate35ms()
    stopBrowserPreview()
    dlg.dismiss()
  end

  renderFilteredAudios("")
end

-- ============================================================================
-- Background Cloud Voice Cloning Worker (With Emotion Instruction & Speed)
-- ============================================================================
local function bgVoiceCloneTask(refAudioPath, scriptText, langCode, xttsLang, instructText, speedVal, tempOutPath, statusFile)
  require "import"
  local File = luajava.bindClass("java.io.File")
  local FileInputStream = luajava.bindClass("java.io.FileInputStream")
  local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
  local BufferedInputStream = luajava.bindClass("java.io.BufferedInputStream")
  local BufferedOutputStream = luajava.bindClass("java.io.BufferedOutputStream")
  local DataOutputStream = luajava.bindClass("java.io.DataOutputStream")
  local BufferedReader = luajava.bindClass("java.io.BufferedReader")
  local InputStreamReader = luajava.bindClass("java.io.InputStreamReader")
  local URL = luajava.bindClass("java.net.URL")
  local String = luajava.bindClass("java.lang.String")
  local StringBuilder = luajava.bindClass("java.lang.StringBuilder")
  local System = luajava.bindClass("java.lang.System")
  local ByteBuffer = luajava.bindClass("java.nio.ByteBuffer")
  local LuaUtil = luajava.bindClass("com.androlua.LuaUtil")

  local function writeStatus(pct, msg)
    pcall(function()
      local f = io.open(statusFile, "w")
      if f then
        f:write(tostring(pct) .. "|" .. tostring(msg))
        f:close()
      end
    end)
  end

  local function jsonEscape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\t", "\\t")
    return s
  end

  local function jsonUnescape(s)
    if not s then return "" end
    s = s:gsub("\\/", "/")
    s = s:gsub("\\\"", "\"")
    s = s:gsub("\\\\", "\\")
    return s
  end

  local function readStreamText(stream)
    if not stream then return "" end
    local reader = BufferedReader(InputStreamReader(stream, "UTF-8"))
    local sb = StringBuilder()
    local line = reader.readLine()
    while line ~= nil do
      sb.append(line).append("\n")
      line = reader.readLine()
    end
    reader.close()
    return tostring(sb.toString())
  end

  local function httpRequestText(method, urlStr, bodyStr, contentType, timeoutMs)
    local conn = nil
    local ok, code, resp = pcall(function()
      local u = URL(urlStr)
      conn = u.openConnection()
      conn.setInstanceFollowRedirects(true)
      conn.setRequestMethod(method)
      conn.setConnectTimeout(timeoutMs or 25000)
      conn.setReadTimeout(timeoutMs or 90000)
      conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; AIVoiceClonerStudio/7.0)")
      conn.setRequestProperty("Accept", "*/*")
      if contentType then
        conn.setRequestProperty("Content-Type", contentType)
      end
      if bodyStr then
        conn.setDoOutput(true)
        local bytes = String(bodyStr).getBytes("UTF-8")
        conn.setFixedLengthStreamingMode(#bytes)
        local outStream = conn.getOutputStream()
        outStream.write(bytes)
        outStream.flush()
        outStream.close()
      end
      local status = conn.getResponseCode()
      local stream = (status >= 200 and status < 400) and conn.getInputStream() or conn.getErrorStream()
      local text = readStreamText(stream)
      return status, text
    end)
    pcall(function() if conn then conn.disconnect() end end)
    if not ok then
      return 0, tostring(code)
    end
    return code, resp
  end

  local function uploadMultipartFile(uploadUrl, filePath)
    local conn = nil
    local ok, code, resp = pcall(function()
      local f = File(filePath)
      local fileName = f.getName()
      local ext = (fileName:match("%.([^%.]+)$") or "wav"):lower()
      local mime = "audio/wav"
      if ext == "mp3" then mime = "audio/mpeg"
      elseif ext == "m4a" or ext == "mp4" or ext == "aac" then mime = "audio/mp4"
      elseif ext == "ogg" or ext == "opus" then mime = "audio/ogg"
      elseif ext == "flac" then mime = "audio/flac" end

      local boundary = "----VoiceClonerBoundary" .. tostring(System.currentTimeMillis())
      local u = URL(uploadUrl)
      conn = u.openConnection()
      conn.setInstanceFollowRedirects(true)
      conn.setRequestMethod("POST")
      conn.setConnectTimeout(30000)
      conn.setReadTimeout(90000)
      conn.setDoInput(true)
      conn.setDoOutput(true)
      conn.setUseCaches(false)
      conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; AIVoiceClonerStudio/7.0)")
      conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" .. boundary)

      local dos = DataOutputStream(conn.getOutputStream())
      dos.writeBytes("--" .. boundary .. "\r\n")
      dos.writeBytes("Content-Disposition: form-data; name=\"files\"; filename=\"" .. fileName .. "\"\r\n")
      dos.writeBytes("Content-Type: " .. mime .. "\r\n\r\n")

      local fis = FileInputStream(f)
      local buf = ByteBuffer.allocate(8192).array()
      local n = fis.read(buf)
      while n ~= -1 do
        dos.write(buf, 0, n)
        n = fis.read(buf)
      end
      fis.close()

      dos.writeBytes("\r\n--" .. boundary .. "--\r\n")
      dos.flush()
      dos.close()

      local status = conn.getResponseCode()
      local stream = (status >= 200 and status < 400) and conn.getInputStream() or conn.getErrorStream()
      local text = readStreamText(stream)
      return status, text
    end)
    pcall(function() if conn then conn.disconnect() end end)
    if not ok then
      return 0, tostring(code)
    end
    return code, resp
  end

  local function downloadFileToDisk(fileUrl, targetPath)
    local conn = nil
    local ok, err = pcall(function()
      local currentUrl = fileUrl
      for _ = 1, 4 do
        local u = URL(currentUrl)
        conn = u.openConnection()
        conn.setInstanceFollowRedirects(true)
        conn.setRequestMethod("GET")
        conn.setConnectTimeout(30000)
        conn.setReadTimeout(90000)
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; AIVoiceClonerStudio/7.0)")
        local status = conn.getResponseCode()
        if status == 301 or status == 302 or status == 303 or status == 307 or status == 308 then
          local loc = conn.getHeaderField("Location")
          conn.disconnect()
          if loc and loc ~= "" then
            currentUrl = loc
          else
            break
          end
        else
          if status < 200 or status >= 400 then
            error("HTTP " .. tostring(status))
          end
          local inStream = conn.getInputStream()
          local copied = pcall(function()
            local fos = FileOutputStream(targetPath)
            LuaUtil.copyFile(inStream, fos)
            fos.flush()
            fos.close()
            inStream.close()
          end)
          if not copied or not File(targetPath).exists() or File(targetPath).length() < 128 then
            local bis = BufferedInputStream(conn.getInputStream())
            local bos = BufferedOutputStream(FileOutputStream(targetPath))
            local buf = ByteBuffer.allocate(8192).array()
            local n = bis.read(buf)
            while n ~= -1 do
              bos.write(buf, 0, n)
              n = bis.read(buf)
            end
            bos.flush()
            bos.close()
            bis.close()
          end
          break
        end
      end
    end)
    pcall(function() if conn then conn.disconnect() end end)
    return ok, err
  end

  local function pollGradioStream(streamUrl)
    local conn = nil
    local resultUrl = nil
    local resultPath = nil
    local lastErr = nil

    local ok, err = pcall(function()
      local u = URL(streamUrl)
      conn = u.openConnection()
      conn.setInstanceFollowRedirects(true)
      conn.setRequestMethod("GET")
      conn.setConnectTimeout(30000)
      conn.setReadTimeout(160000)
      conn.setRequestProperty("Accept", "text/event-stream")
      conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; AIVoiceClonerStudio/7.0)")

      local status = conn.getResponseCode()
      if status < 200 or status >= 400 then
        local errTxt = readStreamText(conn.getErrorStream())
        error("Stream HTTP " .. tostring(status) .. ": " .. tostring(errTxt))
      end

      local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
      local currentEvent = ""
      local line = reader.readLine()
      while line ~= nil do
        if line:match("^event:%s*(.+)$") then
          currentEvent = line:match("^event:%s*(.+)$"):gsub("%s+$", "")
        elseif line:match("^data:%s*(.*)$") then
          local dataStr = line:match("^data:%s*(.*)$")
          if currentEvent == "complete" then
            local uMatch = dataStr:match("\"url\"%s*:%s*\"([^\"]+)\"")
            local pMatch = dataStr:match("\"path\"%s*:%s*\"([^\"]+)\"")
            if uMatch then resultUrl = jsonUnescape(uMatch) end
            if pMatch then resultPath = jsonUnescape(pMatch) end
            if not resultPath then
              local directWav = dataStr:match("\"(/tmp/[^\"]+%.wav)\"") or dataStr:match("\"(/tmp/[^\"]+%.mp3)\"")
              if directWav then resultPath = jsonUnescape(directWav) end
            end
            break
          elseif currentEvent == "error" then
            lastErr = (dataStr ~= "" and dataStr ~= "null") and dataStr or "Voice server is busy."
            break
          elseif currentEvent == "heartbeat" or currentEvent == "generating" then
            writeStatus(68, "Synthesizing natural human voice with selected emotion...")
          end
        end
        line = reader.readLine()
      end
      reader.close()
    end)

    pcall(function() if conn then conn.disconnect() end end)
    if not ok then
      return nil, nil, tostring(err)
    end
    return resultUrl, resultPath, lastErr
  end

  local function cloneOnGradioSpace(spaceSpec)
    local baseUrl = spaceSpec.url
    writeStatus(20, "Connecting to Neural Voice Cloning Server...")

    local apiPrefix = "/gradio_api"
    local infoCode, infoText = httpRequestText("GET", baseUrl .. "/gradio_api/info", nil, nil, 20000)
    if infoCode ~= 200 then
      local code2, text2 = httpRequestText("GET", baseUrl .. "/info", nil, nil, 20000)
      if code2 == 200 then
        apiPrefix = ""
        infoText = text2
      end
    end

    writeStatus(38, "Analyzing human voice sample...")
    local upCode, upResp = uploadMultipartFile(baseUrl .. apiPrefix .. "/upload", refAudioPath)
    if upCode < 200 or upCode >= 300 then
      local altPrefix = (apiPrefix == "/gradio_api") and "" or "/gradio_api"
      upCode, upResp = uploadMultipartFile(baseUrl .. altPrefix .. "/upload", refAudioPath)
      if upCode >= 200 and upCode < 300 then
        apiPrefix = altPrefix
      else
        return nil, "Upload failed (HTTP " .. tostring(upCode) .. ")"
      end
    end

    local uploadedPath = upResp:match("\"([^\"]+)\"")
    if not uploadedPath then
      return nil, "Invalid upload response."
    end
    uploadedPath = jsonUnescape(uploadedPath)

    local origName = File(refAudioPath).getName()
    local fileDataJson = string.format(
      "{\"path\":\"%s\",\"url\":\"%s%s/file=%s\",\"orig_name\":\"%s\",\"meta\":{\"_type\":\"gradio.FileData\"}}",
      jsonEscape(uploadedPath),
      baseUrl,
      apiPrefix,
      jsonEscape(uploadedPath),
      jsonEscape(origName)
    )

    local candidates = {}
    if spaceSpec.id == "primary" then
      local omniPayload = string.format(
        "{\"data\":[\"%s\",\"%s\",%s,\"\",\"%s\",32,2.5,true,%.2f,null,true,true]}",
        jsonEscape(scriptText),
        jsonEscape(langCode),
        fileDataJson,
        jsonEscape(instructText or ""),
        speedVal
      )
      table.insert(candidates, { ep = "_clone_fn", payload = omniPayload })
      table.insert(candidates, { ep = "predict", payload = omniPayload })
    elseif spaceSpec.id == "tertiary" then
      local f5Payload = string.format(
        "{\"data\":[%s,\"\",\"%s\",true]}",
        fileDataJson,
        jsonEscape(scriptText)
      )
      table.insert(candidates, { ep = "run_tts", payload = f5Payload })
      table.insert(candidates, { ep = "predict", payload = f5Payload })
    elseif spaceSpec.id == "secondary" then
      local xttsPayload = string.format(
        "{\"data\":[\"%s\",\"%s\",%s,null,false,true,true,true]}",
        jsonEscape(scriptText),
        jsonEscape(xttsLang),
        fileDataJson
      )
      table.insert(candidates, { ep = "predict", payload = xttsPayload })
    end

    if infoText and #infoText > 10 then
      local firstEp = infoText:match("\"/([%w_]+)\"%s*:%s*{%s*\"parameters\"")
      if firstEp and firstEp ~= "_design_fn" then
        local defaultPayload = candidates[1] and candidates[1].payload or "{}"
        table.insert(candidates, 1, { ep = firstEp, payload = defaultPayload })
      end
    end

    writeStatus(55, "Matching human voice tone and emotion...")

    local eventId = nil
    local activeEp = nil
    local lastCallErr = ""

    for _, cand in ipairs(candidates) do
      local callUrl = baseUrl .. apiPrefix .. "/call/" .. cand.ep
      local cCode, cResp = httpRequestText("POST", callUrl, cand.payload, "application/json", 30000)
      if cCode >= 200 and cCode < 300 then
        local eid = cResp:match("\"event_id\"%s*:%s*\"([^\"]+)\"")
        if eid then
          eventId = eid
          activeEp = cand.ep
          break
        end
      else
        lastCallErr = "HTTP " .. tostring(cCode)
      end
    end

    if not eventId then
      return nil, "Server busy (" .. lastCallErr .. ")"
    end

    writeStatus(68, "Generating cloned voice audio...")
    local streamUrl = baseUrl .. apiPrefix .. "/call/" .. activeEp .. "/" .. eventId
    local outUrl, outPath, streamErr = pollGradioStream(streamUrl)

    if not outUrl and not outPath then
      return nil, tostring(streamErr or "No audio returned")
    end

    local finalDownloadUrl = outUrl
    if not finalDownloadUrl or not finalDownloadUrl:match("^https?://") then
      finalDownloadUrl = baseUrl .. apiPrefix .. "/file=" .. tostring(outPath or outUrl)
    end

    writeStatus(88, "Preparing audio for preview...")
    pcall(function() File(tempOutPath).delete() end)
    local dlOk, dlErr = downloadFileToDisk(finalDownloadUrl, tempOutPath)
    if not dlOk or not File(tempOutPath).exists() or File(tempOutPath).length() < 128 then
      return nil, "Audio fetch error: " .. tostring(dlErr)
    end

    return tempOutPath, nil
  end

  local servers = {
    { id = "primary", url = "https://k2-fsa-omnivoice.hf.space" },
    { id = "secondary", url = "https://hasanbasbunar-voice-cloning-xtts-v2.hf.space" },
    { id = "tertiary", url = "https://mrfakename-e2-f5-tts.hf.space" }
  }

  local lastErr = ""
  for _, srv in ipairs(servers) do
    local outPath, err = cloneOnGradioSpace(srv)
    if outPath then
      writeStatus(100, "SUCCESS|" .. outPath)
      return "SUCCESS|" .. outPath
    else
      lastErr = tostring(err)
    end
  end

  return "ERROR|" .. lastErr
end

-- ============================================================================
-- Button Click Handlers (Every Action Vibrates 35ms)
-- ============================================================================
btnSelectSample.onClick = function()
  vibrate35ms()
  showInToolAudioPicker()
end

btnFavoriteVoices.onClick = function()
  vibrate35ms()
  showFavoriteVoicesWindow()
end

btnAddFavorite.onClick = function()
  vibrate35ms()
  showAddToFavoritesDialog()
end

btnRecordSample.onClick = function()
  vibrate35ms()
  stopSamplePlayback()
  stopOutputPlayback()

  if state.isRecording then
    local ok = pcall(function()
      if state.recorder then
        state.recorder.stop()
        state.recorder.release()
      end
    end)
    state.recorder = nil
    state.isRecording = false
    playRecordStudioChime(false)
    btnRecordSample.setText("RECORD VOICE")
    styleActionButton(btnRecordSample, "#DC2626", "#FCA5A5", "#FFFFFF", 18, 14, 20)

    if ok and File(TEMP_RECORD_FILE).exists() and File(TEMP_RECORD_FILE).length() > 1000 then
      state.refAudioPath = TEMP_RECORD_FILE
      state.refDisplayName = "Recorded Voice Sample"
      updateSampleUI()
      speakText("Voice sample attached.")
    else
      speakText("Recording was too short. Please record at least 4 seconds.")
    end
    return
  end

  playRecordStudioChime(true)
  pcall(function() File(TEMP_RECORD_FILE).delete() end)

  Handler().postDelayed(Runnable{
    run = function()
      local ok, err = pcall(function()
        local mr = MediaRecorder()
        mr.setAudioSource(MediaRecorder.AudioSource.MIC)
        mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        mr.setAudioSamplingRate(44100)
        mr.setAudioEncodingBitRate(128000)
        mr.setAudioChannels(1)
        mr.setOutputFile(TEMP_RECORD_FILE)
        mr.prepare()
        mr.start()
        state.recorder = mr
        state.isRecording = true
      end)

      if ok then
        btnRecordSample.setText("STOP RECORDING")
        styleActionButton(btnRecordSample, "#B91C1C", "#FDE047", "#FFFFFF", 18, 14, 20)
      else
        state.recorder = nil
        state.isRecording = false
        speakText("Recording failed: " .. tostring(err))
      end
    end
  }, 240)
end

btnPlaySample.onClick = function()
  vibrate35ms()
  stopOutputPlayback()
  if state.isSamplePlaying then
    stopSamplePlayback()
    return
  end
  if state.refAudioPath == "" or not File(state.refAudioPath).exists() then
    speakText("Please select a voice sample first.")
    return
  end
  pcall(function()
    local mp = MediaPlayer()
    mp.setDataSource(state.refAudioPath)
    mp.prepare()
    mp.start()
    state.samplePlayer = mp
    state.isSamplePlaying = true
    btnPlaySample.setText("PAUSE SAMPLE")
    styleActionButton(btnPlaySample, "#D97706", "#FDE047", "#FFFFFF", 18, 14, 18)
    mp.setOnCompletionListener(MediaPlayer.OnCompletionListener{
      onCompletion = function()
        stopSamplePlayback()
      end
    })
  end)
end

btnLanguage.onClick = function()
  vibrate35ms()
  showStyledSelectorWindow("Select Target Language", LANGUAGES, state.langIndex, function(idx)
    state.langIndex = idx
    updateSettingsUI()
    speakText("Language: " .. LANGUAGES[idx].name)
  end)
end

btnEmotion.onClick = function()
  vibrate35ms()
  showStyledSelectorWindow("Select Voice Emotion (20 Styles)", EMOTIONS, state.emotionIndex, function(idx)
    state.emotionIndex = idx
    updateSettingsUI()
    speakText("Emotion: " .. EMOTIONS[idx].name)
  end)
end

btnSpeed.onClick = function()
  vibrate35ms()
  showStyledSelectorWindow("Select Voice Speed", SPEEDS, state.speedIndex, function(idx)
    state.speedIndex = idx
    updateSettingsUI()
    speakText("Voice Speed: " .. SPEEDS[idx].name)
  end)
end

btnGenerate.onClick = function()
  vibrate35ms()
  if state.isGenerating then
    speakText("Please wait, voice cloning is already running.")
    return
  end

  if state.refAudioPath == "" or not File(state.refAudioPath).exists() then
    speakText("Please select or record a voice sample first.")
    return
  end

  local rawScript = tostring(etScript.getText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if rawScript == "" then
    speakText("Please enter text in the script box first.")
    return
  end

  local cleanScript = normalizeUrduScript(rawScript)

  stopSamplePlayback()
  stopOutputPlayback()
  stopProgressTicker()
  acquireWakeLock()

  state.isGenerating = true
  outputControlsOuter.setVisibility(View.GONE)
  btnGenerate.setText("CLONING VOICE... PLEASE WAIT")
  styleActionButton(btnGenerate, "#334155", "#94A3B8", "#FFFFFF", 22, 20, 24)
  progressBar.setVisibility(View.VISIBLE)
  progressBar.setProgress(10)
  tvProgressStatus.setVisibility(View.VISIBLE)
  tvProgressStatus.setText("Starting voice cloning...")
  tvProgressStatus.setTextColor(Color.parseColor("#38BDF8"))
  speakText("Cloning human voice. Please wait.")

  pcall(function()
    local f = io.open(STATUS_FILE, "w")
    if f then f:write("10|Preparing voice sample...") f:close() end
  end)

  local t = Ticker()
  t.Period = 600
  t.onTick = function()
    if not state.isGenerating then return end
    pcall(function()
      local f = io.open(STATUS_FILE, "r")
      if f then
        local line = f:read("*a")
        f:close()
        if line and line ~= "" then
          local pctStr, msg = line:match("^(%d+)|(.*)$")
          if pctStr and msg and not msg:match("^SUCCESS|") and not msg:match("^ERROR|") then
            progressBar.setProgress(tonumber(pctStr) or 25)
            tvProgressStatus.setText(msg)
          end
        end
      end
    end)
  end
  state.activeTicker = t
  t.start()

  local lang = LANGUAGES[state.langIndex] or LANGUAGES[1]
  local emo = EMOTIONS[state.emotionIndex] or EMOTIONS[1]
  local spd = SPEEDS[state.speedIndex] or SPEEDS[3]
  local finalSpeed = math.max(0.70, math.min(1.35, spd.val * (emo.speedMul or 1.0)))

  task(
    bgVoiceCloneTask,
    state.refAudioPath,
    cleanScript,
    lang.code,
    lang.xtts,
    emo.instruct or "",
    finalSpeed,
    TEMP_CLONED_FILE,
    STATUS_FILE,
    function(resultStr)
      stopProgressTicker()
      releaseWakeLock()
      state.isGenerating = false
      btnGenerate.setText("GENERATE CLONED VOICE")
      styleActionButton(btnGenerate, "#059669", "#6EE7B7", "#FFFFFF", 22, 20, 24)

      local res = tostring(resultStr or "")
      if res:match("^SUCCESS|") then
        local outPath = res:match("^SUCCESS|(.*)$")
        state.generatedAudioPath = outPath
        state.customFileName = "Cloned_Voice_" .. os.date("%Y%m%d_%H%M%S")
        progressBar.setVisibility(View.GONE)
        tvProgressStatus.setVisibility(View.GONE)

        tvOutputStatus.setText("Audio Ready: " .. state.customFileName .. ".wav")
        outputControlsOuter.setVisibility(View.VISIBLE)
        vibrate35ms()
        speakText("Cloned voice audio is ready to play.")
      else
        local errDetail = res:match("^ERROR|(.*)$") or res
        progressBar.setVisibility(View.GONE)
        tvProgressStatus.setVisibility(View.VISIBLE)
        tvProgressStatus.setText("Cloning Failed: " .. errDetail)
        tvProgressStatus.setTextColor(Color.parseColor("#F87171"))
        speakText("Voice cloning failed. " .. errDetail)
      end
    end
  )
end

btnPlayPauseOutput.onClick = function()
  vibrate35ms()
  stopSamplePlayback()
  if state.generatedAudioPath == "" or not File(state.generatedAudioPath).exists() then
    return
  end

  if state.outputPlayer and state.isOutputPlaying then
    pcall(function()
      state.outputPlayer.pause()
      state.isOutputPlaying = false
      state.isOutputPaused = true
      btnPlayPauseOutput.setText("PLAY")
      styleActionButton(btnPlayPauseOutput, "#1D4ED8", "#60A5FA", "#FFFFFF", 18, 12, 20)
    end)
    return
  end

  if state.outputPlayer and state.isOutputPaused then
    local ok = pcall(function()
      state.outputPlayer.start()
      state.isOutputPlaying = true
      state.isOutputPaused = false
      btnPlayPauseOutput.setText("PAUSE")
      styleActionButton(btnPlayPauseOutput, "#D97706", "#FDE047", "#FFFFFF", 18, 12, 20)
    end)
    if ok then return end
  end

  stopOutputPlayback()
  pcall(function()
    local mp = MediaPlayer()
    mp.setDataSource(state.generatedAudioPath)
    mp.prepare()
    mp.start()
    state.outputPlayer = mp
    state.isOutputPlaying = true
    state.isOutputPaused = false
    btnPlayPauseOutput.setText("PAUSE")
    styleActionButton(btnPlayPauseOutput, "#D97706", "#FDE047", "#FFFFFF", 18, 12, 20)
    mp.setOnCompletionListener(MediaPlayer.OnCompletionListener{
      onCompletion = function()
        stopOutputPlayback()
      end
    })
  end)
end

btnRenameOutput.onClick = function()
  vibrate35ms()
  if state.generatedAudioPath == "" or not File(state.generatedAudioPath).exists() then
    return
  end
  showRenameDialog()
end

btnDownloadOutput.onClick = function()
  vibrate35ms()
  if state.generatedAudioPath == "" or not File(state.generatedAudioPath).exists() then
    speakText("Please generate cloned audio first.")
    return
  end

  local baseName = tostring(state.customFileName or "")
  if baseName == "" then
    baseName = "Cloned_Voice_" .. os.date("%Y%m%d_%H%M%S")
  end
  local saveName = baseName .. ".wav"
  local destPath = PUBLIC_DOWNLOAD_DIR .. "/" .. saveName

  local ok, err = pcall(function()
    local LuaUtil = luajava.bindClass("com.androlua.LuaUtil")
    local fis = FileInputStream(state.generatedAudioPath)
    local fos = FileOutputStream(destPath)
    LuaUtil.copyFile(fis, fos)
    fos.flush()
    fos.close()
    fis.close()
  end)

  if ok and File(destPath).exists() then
    pcall(function()
      local MediaScannerConnection = luajava.bindClass("android.media.MediaScannerConnection")
      local pathsArr = String{ destPath }
      local mimesArr = String{ "audio/wav" }
      MediaScannerConnection.scanFile(activity, pathsArr, mimesArr, nil)
    end)
    pcall(function()
      local scanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
      scanIntent.setData(Uri.fromFile(File(destPath)))
      activity.sendBroadcast(scanIntent)
    end)

    tvOutputStatus.setText("Downloaded: " .. saveName)
    speakText("Audio downloaded: " .. saveName)
  else
    speakText("Download failed: " .. tostring(err))
  end
end

btnAbout.onClick = function()
  vibrate35ms()
  showAboutWindow()
end

btnExit.onClick = function()
  vibrate35ms()
  stopProgressTicker()
  releaseWakeLock()
  stopBrowserPreview()
  stopSamplePlayback()
  stopOutputPlayback()
  pcall(function() File(TEMP_RECORD_FILE).delete() end)
  pcall(function() File(TEMP_CLONED_FILE).delete() end)
  activity.finish()
end

function onDestroy()
  stopProgressTicker()
  releaseWakeLock()
  stopBrowserPreview()
  stopSamplePlayback()
  stopOutputPlayback()
  pcall(function()
    if state.recorder then
      state.recorder.stop()
      state.recorder.release()
    end
  end)
  pcall(function() File(TEMP_RECORD_FILE).delete() end)
  pcall(function() File(TEMP_CLONED_FILE).delete() end)
end
