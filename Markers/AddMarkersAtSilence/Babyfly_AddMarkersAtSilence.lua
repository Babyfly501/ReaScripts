-- 脚本名称: Babyfly_AddMarkersAtSilence
-- 功能: 在语音样本的静音区域添加Marker

-- 用户可调整的参数
local SILENCE_THRESHOLD = -60 -- 静音阈值（dB）
local MIN_SILENCE_DURATION = 0.5 -- 最小静音持续时间（秒）
local MIN_VOICE_DURATION = 0.2 -- 最小非静音持续时间（秒，防止短噪声误触发）

-- 获取选中的媒体轨道
local track = reaper.GetSelectedTrack(0, 0)
if not track then
  reaper.ShowMessageBox("请先选择一个轨道！", "错误", 0)
  return
end

-- 获取轨道上的第一个媒体项
local item = reaper.GetTrackMediaItem(track, 0)
if not item then
  reaper.ShowMessageBox("选中的轨道上没有媒体项！", "错误", 0)
  return
end

-- 获取媒体项的Take
local take = reaper.GetActiveTake(item)
if not take then
  reaper.ShowMessageBox("媒体项没有有效的Take！", "错误", 0)
  return
end

-- 获取Take的PCM源
local source = reaper.GetMediaItemTake_Source(take)
if not source then
  reaper.ShowMessageBox("无法获取媒体源！", "错误", 0)
  return
end

-- 创建AudioAccessor
local accessor = reaper.CreateTakeAudioAccessor(take)
if not accessor then
  reaper.ShowMessageBox("无法创建AudioAccessor！", "错误", 0)
  return
end

-- 获取源的采样率和通道数
local sample_rate = reaper.GetMediaSourceSampleRate(source)
local num_channels = reaper.GetMediaSourceNumChannels(source)

-- 初始化变量
local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
local block_size = 1024 -- 每次处理的样本块大小
local silence_threshold = 10^(SILENCE_THRESHOLD / 20) -- 转换为线性幅度
local min_silence_samples = sample_rate * MIN_SILENCE_DURATION
local min_voice_samples = sample_rate * MIN_VOICE_DURATION

-- 用于存储静音区域
local silence_regions = {}
local is_silence = true -- 当前是否处于静音状态
local silence_start = 0
local last_voice_end = 0

-- 创建缓冲区
local audio_buffer = reaper.new_array(block_size * num_channels)
local sample_pos = 0

-- 遍历音频样本
while sample_pos < item_length * sample_rate do
  -- 读取音频块
  audio_buffer.clear()
  local samples_read = reaper.GetAudioAccessorSamples(
    accessor,
    sample_rate,
    num_channels,
    sample_pos / sample_rate,
    block_size,
    audio_buffer
  )
  
  -- 处理每个样本
  for i = 1, samples_read do
    local max_amplitude = 0
    -- 检查所有通道的最大幅度
    for ch = 0, num_channels - 1 do
      local sample = math.abs(audio_buffer[i + ch * samples_read])
      max_amplitude = math.max(max_amplitude, sample)
    end
    
    local current_pos = sample_pos + i
    local time_pos = current_pos / sample_rate
    
    if max_amplitude < silence_threshold then
      -- 当前为静音
      if not is_silence and (current_pos - last_voice_end) >= min_voice_samples then
        -- 从有声到静音，记录静音开始
        silence_start = time_pos
        is_silence = true
      end
    else
      -- 当前为有声
      if is_silence and (current_pos - (silence_start * sample_rate)) >= min_silence_samples then
        -- 从静音到有声，记录静音区域
        table.insert(silence_regions, {start = silence_start, nd = time_pos})
      end
      is_silence = false
      last_voice_end = current_pos
    end
  end
  
  sample_pos = sample_pos + samples_read
end

-- 处理最后一个静音区域（如果存在）
if is_silence and (item_length - silence_start) >= MIN_SILENCE_DURATION then
  table.insert(silence_regions, {start = silence_start, nd = item_length})
end

-- 撤销点
reaper.Undo_BeginBlock()

-- 添加Marker
for i, region in ipairs(silence_regions) do
  local marker_time = item_start + region.start
  reaper.AddProjectMarker(0, false, marker_time, 0, "Silence " .. i, 0)
end

-- 清理AudioAccessor
reaper.DestroyAudioAccessor(accessor)

-- 撤销点结束
reaper.Undo_EndBlock("Add Markers at Silence", -1)

-- 更新时间线
reaper.UpdateArrange()
reaper.ShowMessageBox("已添加 " .. #silence_regions .. " 个Marker", "完成", 0)
