-- Hammerspoon 配置
-- Author MoPiNianYou
-- Inspiration From twricu

--------------------------------------------------------------------------------
-- 常量与配置 (Constants and Configuration)
--------------------------------------------------------------------------------

local CFG_VERSION = "1.2.0"

local CONFIG = {
	NOTIFICATION_TITLE = "念柚嘅Config",
	STATUS_ENABLED_SUFFIX = "已开启",
	STATUS_DISABLED_SUFFIX = "已关闭",
	SYSTEM_STAY_AWAKE_BASE_TEXT = "系统防休眠",
	MARKDOWN_FORMATTER_WARN_TEXT = "未能获取选中文本",
	MUSIC_TRACK_DISPLAY_BASE_TEXT = "菜单栏乐曲随行",

	ICON_SYSTEM_STAY_AWAKE_ON = "☕",
	ICON_SYSTEM_STAY_AWAKE_OFF = "💤",
	ICON_AUDIO_DEVICE_SWITCHER_ON = "🔉",
	ICON_AUDIO_DEVICE_SWITCHER_ERROR = "🔇",
	ICON_MUSIC_TRACK_DISPLAY_ON = "🎵",
	ICON_MUSIC_TRACK_DISPLAY_OFF = "🔕",

	MUSIC_TRACK_DISPLAY_UPDATE_INTERVAL = 1,
	MUSIC_TRACK_DISPLAY_MAX_LENGTH = 26, -- 菜单栏乐曲随行 - 显示文本长度经过预设以适应多数场景 可自定义显示长度

	-- 个性化快捷软件 --
	CAPSLOCK_APP_SHORTCUTS = {
		{ key = "i", appName = "System Settings" },
		{ key = "f", appName = "Finder" },
		{ key = "t", appName = "Terminal" },
		{ key = "a", appName = "Arc" },
		{ key = "s", appName = "Spotify" },
		{ key = "v", appName = "Visual Studio Code" },
		{ key = "w", appName = "WeChat" },
		{ key = "g", appName = "Telegram" },
	},
}

local KEY_CODES = {
	SHIFT_LEFT = 56,
	SHIFT_RIGHT = 60,
	CAPSLOCK_HID = "0x700000039",
	F13_HID = "0x700000068",
	F13_STRING = "f13",
}

local MODIFIER_KEYS = {
	CMD = { "cmd" },
	OPT = { "alt" },
	CTL = { "ctrl" },
	CMD_SFT = { "cmd", "shift" },
	CMD_OPT_CTL = { "cmd", "alt", "ctrl" },
}

local UPDATE_CHECKER = {
	REMOTE_VERSION_URL = "https://raw.githubusercontent.com/MiPoNianYou/macOS-Enhancer/main/Latest-Version.txt",
	CHECK_INTERVAL_HOURS = 24,
	LAST_CHECK_TIME_KEY = "lastCheckTime",

	AVAILABLE_NOTIFICATION_TITLE = "配置更新可用 ✨",
	NEW_NOTIFICATION_MESSAGE = "发现新版本 - %s\n当前版本为 - "
		.. CFG_VERSION
		.. "\n请前往 GitHub 查看更新详情",

	NONEED_NOTIFICATION_TITLE = "暂无配置更新 ✅",
	NONEED_NOTIFICATION_MESSAGE = "已是最新版本 - " .. CFG_VERSION,

	ERROR_NOTIFICATION_TITLE = "检查配置失败 ❌",
	ERROR_NOTIFICATION_MESSAGE = "检查更新失败 请稍后重试或检查网络连接",
}

--------------------------------------------------------------------------------
-- 全局状态与核心模块 (Global State and Core Modules)
--------------------------------------------------------------------------------

local CapsLockManager = {}
CapsLockManager.modal = nil
CapsLockManager.f13Binding = nil

local CycleInputMethods = {
	flagsChangedEvent = nil,
	keyDownEvent = nil,
	isShiftDown = false,
	wasOtherKeyPressed = false,
}

local TabNavigator = {}

local SystemStayAwake = {
	isActive = false,
	menuBarItem = nil,
}

local AudioDeviceSwitcher = {}

local MarkdownFormatter = {}

local MusicTrackDisplay = {
	isStatusKey = "status",
	menuBarItem = nil,
	updateTimer = nil,
	currentTrackInfo = "",
	musicApps = { "Spotify", "Music", "iTunes" },
	appWatcher = nil,
	isMusicAppRunning = false,
}

MusicTrackDisplay.isEnabled = hs.settings.get(MusicTrackDisplay.isStatusKey)
if MusicTrackDisplay.isEnabled == nil then
	MusicTrackDisplay.isEnabled = false
	hs.settings.set(MusicTrackDisplay.isStatusKey, MusicTrackDisplay.isEnabled)
end

local UpdateChecker = {
	timer = nil,
}

--------------------------------------------------------------------------------
-- 通用辅助函数 (Utility Functions)
--------------------------------------------------------------------------------

local function sendKeystroke(modifiers, key)
	hs.eventtap.keyStroke(modifiers, key, 0)
end

local function launchOrFocusApplication(appName)
	hs.application.launchOrFocus(appName)
end

local function showNotification(message, title)
	title = title or CONFIG.NOTIFICATION_TITLE
	hs.notify.new({ title = title, informativeText = message }):send()
end

local function bindKeyInCapsLockModal(key, action, shouldRepeatOrModifiers)
	local modifiers = {}
	local shouldRepeat = false

	if type(shouldRepeatOrModifiers) == "table" then
		modifiers = shouldRepeatOrModifiers
	elseif type(shouldRepeatOrModifiers) == "boolean" then
		shouldRepeat = shouldRepeatOrModifiers
	end
	CapsLockManager:bindKey(key, action, shouldRepeat, modifiers)
end

local function getLocalizedAudioDeviceName(originalName)
	if originalName == "Built-in Output" then
		return "内置输出"
	end
	return originalName
end

--------------------------------------------------------------------------------
-- CapsLock 键重映射模块 (CapsLock Remapping Module)
--------------------------------------------------------------------------------

function CapsLockManager:initialize()
	self.modal = hs.hotkey.modal.new()
	self.f13Binding = nil
end

function CapsLockManager:remap()
	if not self.modal then
		self:initialize()
	end
	local command = string.format(
		'hidutil property --set \'{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc": %s, "HIDKeyboardModifierMappingDst": %s}]}\'',
		KEY_CODES.CAPSLOCK_HID,
		KEY_CODES.F13_HID
	)
	if not os.execute(command) then
		showNotification("错误 - CapsLock 映射为 F13 失败")
		return
	end
	self.f13Binding = hs.hotkey.bind({}, KEY_CODES.F13_STRING, function()
		if self.modal then
			self.modal:enter()
		end
	end, function()
		if self.modal then
			self.modal:exit()
		end
	end)
end

function CapsLockManager:restore()
	local command = "hidutil property --set '{\"UserKeyMapping\":[]}'"
	if not os.execute(command) then
		showNotification("错误 - 撤销 CapsLock 映射失败")
	end
	if self.f13Binding then
		self.f13Binding:delete()
		self.f13Binding = nil
	end
	if self.modal then
		self.modal:exit()
		self.modal = nil
	end
end

function CapsLockManager:bindKey(key, action, shouldRepeat, modifiers)
	modifiers = modifiers or {}
	shouldRepeat = shouldRepeat or false
	local pressFunction = function()
		action()
	end
	local releaseFunction = function() end
	local repeatFunction = nil
	if shouldRepeat then
		repeatFunction = pressFunction
	end
	if self.modal then
		self.modal:bind(modifiers, key, pressFunction, releaseFunction, repeatFunction)
	else
		showNotification("错误 - CapsLock 模态未初始化 无法绑定按键 - " .. key)
	end
end

function CapsLockManager:bindAppLaunchers(appShortcuts)
	if not self.modal then
		showNotification("错误 - CapsLock 模态未初始化 无法绑定应用启动器")
		return
	end
	for _, shortcut in ipairs(appShortcuts) do
		self:bindKey(shortcut.key, function()
			launchOrFocusApplication(shortcut.appName)
		end)
	end
end

--------------------------------------------------------------------------------
-- 功能模块 - 循环切换输入法 (Cycle Input Methods Module)
--------------------------------------------------------------------------------

local function getAllInputSourceIDs()
	local sources = {}
	local layouts = hs.keycodes.layouts(true)
	for _, sourceID in pairs(layouts) do
		table.insert(sources, sourceID)
	end
	local methods = hs.keycodes.methods(true)
	for _, sourceID in pairs(methods) do
		if not hs.fnutils.contains(sources, sourceID) then
			table.insert(sources, sourceID)
		end
	end
	return sources
end

local function cycleToNextInputMethod()
	local availableSources = getAllInputSourceIDs()
	if #availableSources < 2 then
		return
	end
	local currentSourceID = hs.keycodes.currentSourceID()
	local currentIndex = 1
	for i, id in ipairs(availableSources) do
		if id == currentSourceID then
			currentIndex = i
			break
		end
	end
	local nextIndex = (currentIndex % #availableSources) + 1
	hs.keycodes.currentSourceID(availableSources[nextIndex])
end

function CycleInputMethods:start()
	self.flagsChangedEvent = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
		local keyCode = event:getProperty(hs.eventtap.event.properties.keyboardEventKeycode)
		local flags = event:getFlags()
		if keyCode == KEY_CODES.SHIFT_LEFT or keyCode == KEY_CODES.SHIFT_RIGHT then
			if flags:containExactly({ "shift" }) and not self.isShiftDown then
				self.isShiftDown = true
				self.wasOtherKeyPressed = false
			elseif not flags["shift"] and self.isShiftDown then
				if not self.wasOtherKeyPressed then
					cycleToNextInputMethod()
				end
				self.isShiftDown = false
			end
		elseif self.isShiftDown and not flags["shift"] then
			self.isShiftDown = false
		end
		return false
	end)
	if self.flagsChangedEvent then
		self.flagsChangedEvent:start()
	end
	self.keyDownEvent = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function()
		if self.isShiftDown then
			self.wasOtherKeyPressed = true
		end
		return false
	end)
	if self.keyDownEvent then
		self.keyDownEvent:start()
	end
end

function CycleInputMethods:stop()
	if self.flagsChangedEvent then
		self.flagsChangedEvent:stop()
		self.flagsChangedEvent = nil
	end
	if self.keyDownEvent then
		self.keyDownEvent:stop()
		self.keyDownEvent = nil
	end
	self.isShiftDown = false
	self.wasOtherKeyPressed = false
end

--------------------------------------------------------------------------------
-- 功能模块 - 软件标签页导航 (Tab Navigation Module)
--------------------------------------------------------------------------------

function TabNavigator:previous()
	sendKeystroke(MODIFIER_KEYS.CMD_SFT, "[")
end
function TabNavigator:next()
	sendKeystroke(MODIFIER_KEYS.CMD_SFT, "]")
end

--------------------------------------------------------------------------------
-- 功能模块 - 系统防休眠守护 (System Stay-Awake Module)
--------------------------------------------------------------------------------

local function cleanupStayAwake()
	hs.caffeinate.set("displayIdle", false, false)
	if SystemStayAwake.menuBarItem then
		SystemStayAwake.menuBarItem:delete()
		SystemStayAwake.menuBarItem = nil
	end
end

function SystemStayAwake:toggle()
	self.isActive = not self.isActive
	local statusText
	local notificationText
	if self.isActive then
		statusText = CONFIG.SYSTEM_STAY_AWAKE_BASE_TEXT .. CONFIG.STATUS_ENABLED_SUFFIX
		notificationText = statusText .. " " .. CONFIG.ICON_SYSTEM_STAY_AWAKE_ON
		hs.caffeinate.set("displayIdle", true, true)
		if not self.menuBarItem then
			self.menuBarItem = hs.menubar.new()
		end
		self.menuBarItem:setTitle(CONFIG.ICON_SYSTEM_STAY_AWAKE_ON)
		self.menuBarItem:setTooltip(CONFIG.SYSTEM_STAY_AWAKE_BASE_TEXT .. " " .. CONFIG.STATUS_ENABLED_SUFFIX)
	else
		statusText = CONFIG.SYSTEM_STAY_AWAKE_BASE_TEXT .. CONFIG.STATUS_DISABLED_SUFFIX
		notificationText = statusText .. " " .. CONFIG.ICON_SYSTEM_STAY_AWAKE_OFF
		cleanupStayAwake()
	end
	showNotification(notificationText)
end

function SystemStayAwake:stop()
	cleanupStayAwake()
	self.isActive = false
end

--------------------------------------------------------------------------------
-- 功能模块 - 输出设备切换器 (Audio Device Switcher Module)
--------------------------------------------------------------------------------

function AudioDeviceSwitcher:cycleOutput()
	local outputs = hs.audiodevice.allOutputDevices()
	if not outputs or #outputs == 0 then
		showNotification("未找到音频输出设备" .. " " .. CONFIG.ICON_AUDIO_DEVICE_SWITCHER_ERROR)
		return
	end

	if #outputs == 1 then
		local deviceName = getLocalizedAudioDeviceName(outputs[1]:name())
		showNotification(
			"只有一个音频输出设备 - " .. deviceName .. " " .. CONFIG.ICON_AUDIO_DEVICE_SWITCHER_ON
		)
		return
	end

	local currentDevice = hs.audiodevice.defaultOutputDevice()
	local currentIndex = -1

	if currentDevice then
		for i, device in ipairs(outputs) do
			if device:uid() == currentDevice:uid() then
				currentIndex = i
				break
			end
		end
	end

	local nextIndex
	if currentIndex == -1 or currentIndex == #outputs then
		nextIndex = 1
	else
		nextIndex = currentIndex + 1
	end

	local nextDevice = outputs[nextIndex]
	if nextDevice then
		local success = nextDevice:setDefaultOutputDevice()
		local displayName = getLocalizedAudioDeviceName(nextDevice:name())

		if success then
			showNotification(
				"音频输出已切换至 - " .. displayName .. " " .. CONFIG.ICON_AUDIO_DEVICE_SWITCHER_ON
			)
		else
			showNotification(
				"错误 - 切换音频输出至 " .. displayName .. " " .. CONFIG.ICON_AUDIO_DEVICE_SWITCHER_ERROR
			)
		end
	else
		showNotification("错误 - 无法确定下一个音频设备" .. " " .. CONFIG.ICON_AUDIO_DEVICE_SWITCHER_ERROR)
	end
end

--------------------------------------------------------------------------------
-- 功能模块 - Markdown 格式化 (Markdown Formatting Module)
--------------------------------------------------------------------------------

local function applyMarkdownFormatting(formatFunction, failureMessage)
	local pasteboard = hs.pasteboard
	local originalClipboardContents = pasteboard.getContents()
	failureMessage = failureMessage or CONFIG.MARKDOWN_FORMATTER_WARN_TEXT
	sendKeystroke(MODIFIER_KEYS.CMD, "c")
	hs.timer.doAfter(0.2, function()
		local selectedText = pasteboard.getContents()
		if selectedText == nil or selectedText == originalClipboardContents then
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end
			showNotification(failureMessage)
			return
		end
		local formattedText = formatFunction(selectedText)
		pasteboard.setContents(formattedText)
		sendKeystroke(MODIFIER_KEYS.CMD, "v")
		hs.timer.doAfter(0.2, function()
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end
		end)
	end)
end

function MarkdownFormatter:wrapSelectedText(prefix, suffix)
	applyMarkdownFormatting(function(text)
		return prefix .. text .. suffix
	end)
end
function MarkdownFormatter:blockquote()
	applyMarkdownFormatting(function(text)
		local lines = {}
		for line in string.gmatch(text, "([^\r\n]*)") do
			table.insert(lines, "> " .. line)
		end
		return table.concat(lines, "\n")
	end)
end
function MarkdownFormatter:bold()
	self:wrapSelectedText("**", "**")
end
function MarkdownFormatter:italic()
	self:wrapSelectedText("*", "*")
end
function MarkdownFormatter:strikethrough()
	self:wrapSelectedText("~~", "~~")
end
function MarkdownFormatter:code()
	self:wrapSelectedText("`", "`")
end
function MarkdownFormatter:inlineLinkPlaceholder()
	applyMarkdownFormatting(function(text)
		return "[" .. text .. "]()"
	end, CONFIG.MARKDOWN_FORMATTER_WARN_TEXT .. "作为链接文本")
	hs.timer.doAfter(0.3, function()
		sendKeystroke({}, "left")
	end)
end

--------------------------------------------------------------------------------
-- 功能模块 - 菜单栏乐曲随行 (Music Now Playing Display Module)
--------------------------------------------------------------------------------

local function checkMusicAppRunning()
	local runningApps = hs.application.runningApplications()
	for _, appName in ipairs(MusicTrackDisplay.musicApps) do
		for _, runningApp in ipairs(runningApps) do
			if runningApp:name() == appName then
				return true
			end
		end
	end
	return false
end

local function getCurrentTrackInfo()
	if not MusicTrackDisplay.isMusicAppRunning or not MusicTrackDisplay.isEnabled then
		return nil
	end

	local trackInfo = nil
	local artist = nil
	local track = nil

	if hs.spotify and hs.application.find("Spotify") and hs.application.find("Spotify"):isRunning() then
		if hs.spotify.isPlaying() then
			artist = hs.spotify.getCurrentArtist()
			track = hs.spotify.getCurrentTrack()
			if artist and track and artist ~= "" and track ~= "" then
				trackInfo = track .. " · " .. artist
			end
		end
	end

	if not trackInfo and hs.itunes and hs.application.find("Music") and hs.application.find("Music"):isRunning() then
		if hs.itunes.isPlaying() then
			artist = hs.itunes.getCurrentArtist()
			track = hs.itunes.getCurrentTrack()
			if artist and track and artist ~= "" and track ~= "" then
				trackInfo = track .. " · " .. artist
			end
		end
	elseif
		not trackInfo
		and hs.itunes
		and hs.application.find("iTunes")
		and hs.application.find("iTunes"):isRunning()
	then
		if hs.itunes.isPlaying() then
			artist = hs.itunes.getCurrentArtist()
			track = hs.itunes.getCurrentTrack()
			if artist and track and artist ~= "" and track ~= "" then
				trackInfo = track .. " · " .. artist
			end
		end
	end

	return trackInfo
end

function MusicTrackDisplay:updateMenuBar()
	if not self.isEnabled then
		if self.menuBarItem then
			self.menuBarItem:delete()
			self.menuBarItem = nil
		end
		self.currentTrackInfo = ""
		return
	end

	local trackInfo = getCurrentTrackInfo()

	if trackInfo then
		if trackInfo ~= self.currentTrackInfo then
			self.currentTrackInfo = trackInfo
			if not self.menuBarItem then
				self.menuBarItem = hs.menubar.new()
			end
			if self.menuBarItem then
				local displayTitle = CONFIG.ICON_MUSIC_TRACK_DISPLAY_ON .. " " .. trackInfo
				if string.len(displayTitle) > CONFIG.MUSIC_TRACK_DISPLAY_MAX_LENGTH then
					displayTitle = string.sub(displayTitle, 1, CONFIG.MUSIC_TRACK_DISPLAY_MAX_LENGTH) .. "..."
				end
				self.menuBarItem:setTitle(displayTitle)
				self.menuBarItem:setTooltip(trackInfo)
			end
		end
	else
		if self.currentTrackInfo ~= "" or self.menuBarItem then
			self.currentTrackInfo = ""
			if self.menuBarItem then
				self.menuBarItem:delete()
				self.menuBarItem = nil
			end
		end
	end
end

function MusicTrackDisplay:_manageUpdateTimer()
	if self.isEnabled and self.isMusicAppRunning then
		if not self.updateTimer then
			self:updateMenuBar()
			self.updateTimer = hs.timer.doEvery(CONFIG.MUSIC_TRACK_DISPLAY_UPDATE_INTERVAL, function()
				self:updateMenuBar()
			end)
		end
	else
		if self.updateTimer then
			self.updateTimer:stop()
			self.updateTimer = nil
			self:updateMenuBar()
		end
	end
end

local function musicAppCallback(appName, eventType, appObject)
	if hs.fnutils.contains(MusicTrackDisplay.musicApps, appName) then
		local wasRunning = MusicTrackDisplay.isMusicAppRunning
		if eventType == hs.application.watcher.launched or eventType == hs.application.watcher.activated then
			MusicTrackDisplay.isMusicAppRunning = true
			if not wasRunning then
				MusicTrackDisplay:_manageUpdateTimer()
			end
		elseif eventType == hs.application.watcher.terminated then
			MusicTrackDisplay.isMusicAppRunning = checkMusicAppRunning()
			if wasRunning and not MusicTrackDisplay.isMusicAppRunning then
				MusicTrackDisplay:_manageUpdateTimer()
			end
		end
	end
end

function MusicTrackDisplay:start()
	if not self.appWatcher then
		self.appWatcher = hs.application.watcher.new(musicAppCallback)
		self.appWatcher:start()
	end
	self.isMusicAppRunning = checkMusicAppRunning()
	self:_manageUpdateTimer()
end

function MusicTrackDisplay:stop()
	if self.appWatcher then
		self.appWatcher:stop()
		self.appWatcher = nil
	end
	self.isMusicAppRunning = false
	if self.updateTimer then
		self.updateTimer:stop()
		self.updateTimer = nil
	end
	if self.menuBarItem then
		self.menuBarItem:delete()
		self.menuBarItem = nil
	end
	self.currentTrackInfo = ""
end

function MusicTrackDisplay:toggle()
	self.isEnabled = not self.isEnabled
	hs.settings.set(MusicTrackDisplay.isStatusKey, self.isEnabled)
	local statusText
	local notificationText
	if self.isEnabled then
		statusText = CONFIG.MUSIC_TRACK_DISPLAY_BASE_TEXT .. CONFIG.STATUS_ENABLED_SUFFIX
		notificationText = statusText .. " " .. CONFIG.ICON_MUSIC_TRACK_DISPLAY_ON
		self:start()
	else
		statusText = CONFIG.MUSIC_TRACK_DISPLAY_BASE_TEXT .. CONFIG.STATUS_DISABLED_SUFFIX
		notificationText = statusText .. " " .. CONFIG.ICON_MUSIC_TRACK_DISPLAY_OFF
		self:stop()
	end
	showNotification(notificationText)
end

--------------------------------------------------------------------------------
-- 功能模块 - 配置档更新检测 (Update Checker Module)
--------------------------------------------------------------------------------

local function isVersionGreaterThan(versionA, versionB)
	local partsA = {}
	for part in string.gmatch(versionA, "[^%.]+") do
		table.insert(partsA, tonumber(part))
	end
	local partsB = {}
	for part in string.gmatch(versionB, "[^%.]+") do
		table.insert(partsB, tonumber(part))
	end

	for i = 1, math.max(#partsA, #partsB) do
		local numA = partsA[i] or 0
		local numB = partsB[i] or 0
		if numA > numB then
			return true
		end
		if numA < numB then
			return false
		end
	end
	return false
end

function UpdateChecker:performCheck(isManualCheck)
	isManualCheck = isManualCheck or false

	if not isManualCheck and UPDATE_CHECKER.CHECK_INTERVAL_HOURS and UPDATE_CHECKER.CHECK_INTERVAL_HOURS > 0 then
		local lastCheckTime = hs.settings.get(UPDATE_CHECKER.LAST_CHECK_TIME_KEY) or 0
		local currentTime = os.time()
		local intervalSeconds = UPDATE_CHECKER.CHECK_INTERVAL_HOURS * 60 * 60

		if (currentTime - lastCheckTime) < intervalSeconds then
			return
		end
	end

	if isManualCheck then
		showNotification("正在检查更新", CONFIG.NOTIFICATION_TITLE)
	end

	hs.http.asyncGet(UPDATE_CHECKER.REMOTE_VERSION_URL, nil, function(statusCode, responseBody, headers)
		if statusCode == 200 and responseBody then
			local remoteVersion = string.match(responseBody, "^([%d%.]+)")
			if remoteVersion then
				remoteVersion = remoteVersion:gsub("^%s*(.-)%s*$", "%1")

				if isVersionGreaterThan(remoteVersion, CFG_VERSION) then
					showNotification(
						string.format(UPDATE_CHECKER.NEW_NOTIFICATION_MESSAGE, remoteVersion),
						UPDATE_CHECKER.AVAILABLE_NOTIFICATION_TITLE
					)
				elseif isManualCheck then
					showNotification(
						UPDATE_CHECKER.NONEED_NOTIFICATION_MESSAGE,
						UPDATE_CHECKER.NONEED_NOTIFICATION_TITLE
					)
				end
				hs.settings.set(UPDATE_CHECKER.LAST_CHECK_TIME_KEY, os.time())
			end
		else
			if isManualCheck or not hs.settings.get(UPDATE_CHECKER.LAST_CHECK_TIME_KEY) then
				showNotification(
					UPDATE_CHECKER.ERROR_NOTIFICATION_MESSAGE .. "/n错误代码 - HTTP " .. statusCode,
					UPDATE_CHECKER.ERROR_NOTIFICATION_TITLE
				)
			end
		end
	end)
end

function UpdateChecker:start()
	if UPDATE_CHECKER.CHECK_INTERVAL_HOURS and UPDATE_CHECKER.CHECK_INTERVAL_HOURS > 0 then
		self:performCheck(false)

		if self.timer then
			self.timer:stop()
		end
		self.timer = hs.timer.doEvery(UPDATE_CHECKER.CHECK_INTERVAL_HOURS * 60 * 60, function()
			self:performCheck(false)
		end)
	else
		self:performCheck(false)
	end
end

function UpdateChecker:stop()
	if self.timer then
		self.timer:stop()
		self.timer = nil
	end
end

function UpdateChecker:checkManually()
	self:performCheck(true)
end

--------------------------------------------------------------------------------
-- 配置初始化与快捷键绑定 (Initialization & Key Bindings)
--------------------------------------------------------------------------------

local function initializeConfiguration()
	CapsLockManager:initialize()
	CapsLockManager:remap()

	-- 应用快速启动器 --
	CapsLockManager:bindAppLaunchers(CONFIG.CAPSLOCK_APP_SHORTCUTS)

	-- 循环切换输入法 --
	CycleInputMethods:start()

	-- 软件标签页导航 --
	bindKeyInCapsLockModal("left", function()
		TabNavigator:previous() -- 上一页
	end)
	bindKeyInCapsLockModal("right", function()
		TabNavigator:next() -- 下一页
	end)

	-- 系统防休眠守护 --
	bindKeyInCapsLockModal("p", function()
		SystemStayAwake:toggle()
	end, MODIFIER_KEYS.CTL)

	-- 输出设备切换器 --
	bindKeyInCapsLockModal("a", function()
		AudioDeviceSwitcher:cycleOutput()
	end, MODIFIER_KEYS.CTL)

	-- Markdown 格式化 --
	bindKeyInCapsLockModal("q", function()
		MarkdownFormatter:blockquote() -- 套引用块
	end, MODIFIER_KEYS.OPT)
	bindKeyInCapsLockModal("b", function()
		MarkdownFormatter:bold() -- 加粗文本
	end, MODIFIER_KEYS.OPT)
	bindKeyInCapsLockModal("i", function()
		MarkdownFormatter:italic() -- 斜体文本
	end, MODIFIER_KEYS.OPT)
	bindKeyInCapsLockModal("s", function()
		MarkdownFormatter:strikethrough() -- 删除文本
	end, MODIFIER_KEYS.OPT)
	bindKeyInCapsLockModal("k", function()
		MarkdownFormatter:code() -- 代码语法
	end, MODIFIER_KEYS.OPT)
	bindKeyInCapsLockModal("l", function()
		MarkdownFormatter:inlineLinkPlaceholder() -- 链接语法
	end, MODIFIER_KEYS.OPT)

	-- 菜单栏乐曲随行 --
	bindKeyInCapsLockModal("s", function()
		MusicTrackDisplay:toggle()
	end, MODIFIER_KEYS.CTL)
	if MusicTrackDisplay.isEnabled then
		MusicTrackDisplay:start()
	end

	-- 配置档更新检测 --
	hs.hotkey.bind(MODIFIER_KEYS.CMD_OPT_CTL, "u", function()
		UpdateChecker:checkManually()
	end)

	-- 配置即时热重载 --
	hs.hotkey.bind(MODIFIER_KEYS.CMD_OPT_CTL, "r", function()
		hs.reload()
	end)
end

--------------------------------------------------------------------------------
-- Hammerspoon 退出时的清理操作 (Shutdown Cleanup)
--------------------------------------------------------------------------------

hs.shutdownCallback = function()
	CapsLockManager:restore()
	CycleInputMethods:stop()
	SystemStayAwake:stop()
	MusicTrackDisplay:stop()
	UpdateChecker:stop()
end

--------------------------------------------------------------------------------
-- 脚本启动 (Script Execution Start)
--------------------------------------------------------------------------------

initializeConfiguration()
showNotification("配置加载成功 ✨")
UpdateChecker:start()
