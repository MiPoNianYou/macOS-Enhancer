-- Hammerspoon 配置
-- Author MoPiNianYou
-- Inspiration From twricu
-- Version 1.0.0

--------------------------------------------------------------------------------
-- 常量与配置 (Constants and Configuration)
--------------------------------------------------------------------------------

local CONFIG = {
	NOTIFICATION_TITLE = "念柚嘅Config",
	SYSTEM_STAY_AWAKE_BASE_TEXT = "系统防休眠",
	STATUS_ENABLED_SUFFIX = "已开启",
	STATUS_DISABLED_SUFFIX = "已关闭",
	ICON_SYSTEM_STAY_AWAKE_ON = "☕",
	ICON_SYSTEM_STAY_AWAKE_OFF = "💤",
    MARKDOWN_FORMATTER_WARN_TEXT = "未能获取选中文本",

    -- 个性化功能定制
	CAPSLOCK_APP_SHORTCUTS = {
		{ key = "f", appName = "Finder" },
		{ key = "t", appName = "Terminal" },
		{ key = "a", appName = "Arc" },
		{ key = "s", appName = "Spotify" },
		{ key = "v", appName = "Visual Studio Code" },
		{ key = "w", appName = "WeChat" },
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
	COMMAND_SHIFT = { "cmd", "shift" },
	COMMAND_OPT_CTL = { "cmd", "alt", "ctrl" },
	COMMAND = { "cmd" },
	OPTION = { "alt" },
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

local SystemStayAwake = {
	isActive = false,
	menuBarItem = nil,
}

local TabNavigator = {}
local MarkdownFormatter = {}

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
		showNotification("错误 - CapsLock 模态未初始化，无法绑定按键 - " .. key)
	end
end

function CapsLockManager:bindAppLaunchers(appShortcuts)
	if not self.modal then
		showNotification("错误 - CapsLock 模态未初始化，无法绑定应用启动器")
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

local function getAllInputSourceIDs_internal()
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

local function cycleToNextInputMethod_internal()
	local availableSources = getAllInputSourceIDs_internal()
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
					cycleToNextInputMethod_internal()
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
-- 功能模块 - 系统防休眠守护 (System Stay-Awake Module)
--------------------------------------------------------------------------------

function SystemStayAwake:toggle()
	self.isActive = not self.isActive
	local statusText
	local notificationText

	if self.isActive then
		statusText = CONFIG.SYSTEM_STAY_AWAKE_BASE_TEXT .. "" .. CONFIG.STATUS_ENABLED_SUFFIX
		notificationText = statusText .. " " .. CONFIG.ICON_SYSTEM_STAY_AWAKE_ON
		hs.caffeinate.set("displayIdle", true, true)
		if not self.menuBarItem then
			self.menuBarItem = hs.menubar.new()
		end
		if self.menuBarItem then
			self.menuBarItem:setTitle(CONFIG.ICON_SYSTEM_STAY_AWAKE_ON)
		end
	else
		statusText = CONFIG.SYSTEM_STAY_AWAKE_BASE_TEXT .. "" .. CONFIG.STATUS_DISABLED_SUFFIX
		notificationText = statusText .. " " .. CONFIG.ICON_SYSTEM_STAY_AWAKE_OFF
		hs.caffeinate.set("displayIdle", false, false)
		if self.menuBarItem then
			self.menuBarItem:delete()
			self.menuBarItem = nil
		end
	end
	showNotification(notificationText)
end

function SystemStayAwake:ensureStopped()
	if self.isActive then
		hs.caffeinate.set("displayIdle", false, false)
		if self.menuBarItem then
			self.menuBarItem:delete()
			self.menuBarItem = nil
		end
		self.isActive = false
	end
end

--------------------------------------------------------------------------------
-- 功能模块 - 软件标签页导航 (Tab Navigation Module)
--------------------------------------------------------------------------------

function TabNavigator:previous()
	sendKeystroke(MODIFIER_KEYS.COMMAND_SHIFT, "[")
end

function TabNavigator:next()
	sendKeystroke(MODIFIER_KEYS.COMMAND_SHIFT, "]")
end

--------------------------------------------------------------------------------
-- 功能模块 - Markdown 格式化 (Markdown Formatting Module)
--------------------------------------------------------------------------------

function MarkdownFormatter:wrapSelectedText(prefix, suffix)
	local pasteboard = hs.pasteboard
	local originalClipboardContents = pasteboard.getContents()

	sendKeystroke(MODIFIER_KEYS.COMMAND, "c")

	hs.timer.doAfter(0.2, function()
		local selectedText = pasteboard.getContents()

		if selectedText == nil then
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end
			showNotification(CONFIG.MARKDOWN_FORMATTER_WARN_TEXT)
			return
		end

		local wrappedText = prefix .. selectedText .. suffix
		pasteboard.setContents(wrappedText)
		sendKeystroke(MODIFIER_KEYS.COMMAND, "v")

		hs.timer.doAfter(0.2, function()
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end
		end)
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
	local pasteboard = hs.pasteboard
	local originalClipboardContents = pasteboard.getContents()

	sendKeystroke(MODIFIER_KEYS.COMMAND, "c")

	hs.timer.doAfter(0.2, function()
		local selectedText = pasteboard.getContents()
		if selectedText == nil then
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end
			showNotification(CONFIG.MARKDOWN_FORMATTER_WARN_TEXT)
			return
		end

		local wrappedText = "[" .. selectedText .. "]()"
		pasteboard.setContents(wrappedText)
		sendKeystroke(MODIFIER_KEYS.COMMAND, "v")

		hs.timer.doAfter(0.2, function()
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end

			hs.timer.doAfter(0.1, function()
				sendKeystroke({}, "left")
			end)
		end)
	end)
end

function MarkdownFormatter:blockquote()
	local pasteboard = hs.pasteboard
	local originalClipboardContents = pasteboard.getContents()

	sendKeystroke(MODIFIER_KEYS.COMMAND, "c")

	hs.timer.doAfter(0.2, function()
		local selectedText = pasteboard.getContents()
		if selectedText == nil then
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end
			showNotification(CONFIG.MARKDOWN_FORMATTER_WARN_TEXT)
			return
		end

		local lines = {}
		for line in string.gmatch(selectedText, "([^\r\n]*)") do
			table.insert(lines, "> " .. line)
		end
		local wrappedText = table.concat(lines, "\n")

		pasteboard.setContents(wrappedText)
		sendKeystroke(MODIFIER_KEYS.COMMAND, "v")

		hs.timer.doAfter(0.2, function()
			if originalClipboardContents ~= nil then
				pasteboard.setContents(originalClipboardContents)
			else
				pasteboard.setContents("")
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- 配置初始化与快捷键绑定 (Initialization & Key Bindings)
--------------------------------------------------------------------------------

local function initializeConfiguration()
	CapsLockManager:initialize()
	CapsLockManager:remap()

	CapsLockManager:bindAppLaunchers(CONFIG.CAPSLOCK_APP_SHORTCUTS) -- 应用快速启动器

	CycleInputMethods:start() -- 循环切换输入法

	bindKeyInCapsLockModal("p", function()
		SystemStayAwake:toggle() -- 系统防休眠守护
	end)

	bindKeyInCapsLockModal("left", function()
		TabNavigator:previous() -- 软件标签页导航 - 上一页
	end)
	bindKeyInCapsLockModal("right", function()
		TabNavigator:next() -- 软件标签页导航 - 下一页
	end)

	bindKeyInCapsLockModal("b", function()
		MarkdownFormatter:bold() -- Markdown 格式化 - 加粗文本
	end, MODIFIER_KEYS.OPTION)
	bindKeyInCapsLockModal("i", function()
		MarkdownFormatter:italic() -- Markdown 格式化 - 斜体文本
	end, MODIFIER_KEYS.OPTION)
	bindKeyInCapsLockModal("s", function()
		MarkdownFormatter:strikethrough() -- Markdown 格式化 - 删除文本
	end, MODIFIER_KEYS.OPTION)
	bindKeyInCapsLockModal("k", function()
		MarkdownFormatter:code() -- Markdown 格式化 - 代码语法
	end, MODIFIER_KEYS.OPTION)
	bindKeyInCapsLockModal("l", function()
		MarkdownFormatter:inlineLinkPlaceholder() -- Markdown 格式化 - 链接语法
	end, MODIFIER_KEYS.OPTION)
	bindKeyInCapsLockModal("q", function()
		MarkdownFormatter:blockquote() -- Markdown 格式化 - 套引用块
	end, MODIFIER_KEYS.OPTION)

	hs.hotkey.bind(MODIFIER_KEYS.COMMAND_OPT_CTL, "R", function()
		hs.reload() -- 配置即时热重载
	end)
end

--------------------------------------------------------------------------------
-- Hammerspoon 退出时的清理操作 (Shutdown Cleanup)
--------------------------------------------------------------------------------

hs.shutdownCallback = function()
	CapsLockManager:restore()
	CycleInputMethods:stop()
	SystemStayAwake:ensureStopped()
end

--------------------------------------------------------------------------------
-- 脚本启动 (Script Execution Start)
--------------------------------------------------------------------------------

initializeConfiguration()
showNotification("配置加载成功 ✨")
