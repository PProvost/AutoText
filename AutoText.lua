--[[
Name: AutoText\AutoText.lua
Description: Keeps track of your favorite things to say

Copyright 2008 Quaiche

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
]]

AutoText = LibStub("AceAddon-3.0"):NewAddon("AutoText", "AceConsole-3.0", "AceEvent-3.0")
AutoText.revision = tonumber(("$Revision: 67 $"):match("%d+"))
AutoText.date = ("$Date: 2011-05-30 22:12:01 -0600 (Mon, 30 May 2011) $"):match("%d%d%d%d%-%d%d%-%d%d")

local db = nil -- Local profile database
local lastWhisperSentBy = nil -- Who sent the last /w to us?

local defaults = {
	profile = {
		messages = { },
	}
}

local function CreateSafeTableKey(name)
	-- TODO: Check to see if this is unique or not and append 1,2,3 etc if not
	return string.gsub(name, "%s", "_")
end

local function GetOptions()
	local options = {
		name = "AutoText",
		type = "group",
		handler = AutoText,
		args = {
			messages = {
				name = "Messages",
				type = "group",
				args = {
					add = {
						name = "Add New Message",
						desc = "Add a new element with the given name",
						type = "input",
						set = function(info,val) 
							shortcutName = CreateSafeTableKey(val)
							db.messages[shortcutName] = { name=val, content = "", chatType = "SAY", category="General" } 
						end,
					}
				}
			},
		}
	}

	for k,v in pairs(db.messages) do
		if v.category == nil or v.category == "" then 
			v.category = "General"
		end
		local safeCatName = CreateSafeTableKey(v.category)
		if options.args.messages.args[safeCatName] == nil then
			options.args.messages.args[safeCatName] = {
				name = v.category,
				type = 'group',
				args = {}
			}
		end
		options.args.messages.args[safeCatName].args[k] = {
			name = v.name,
			type = "group",
			args = {
				header = {
					type = "header",
					name = "Details",
					order = 0,
				},
				shortcut = {
					name = "Shortcut",
					desc = "Slash command shortcut",
					type = "input",
					order = 1,
					get = function() return k end,
					set = function(info,val)
						-- TODO: Check to see if this is unique and if not, pop a confirmation
						local tmp = v
						db.messages[k] = nil
						db.messages[val] = tmp
					end,
					validate = function(info,val) return string.find(val, "%s") == nil end,
					usage = "The shortcut name may not contain spaces.",
				},
				name = {
					name = "Name",
					desc = "Name",
					type = "input",
					width = "double",
					order = 1,
					set = function(info,val) v.name = val end,
					get = function() return v.name or "" end,
				},
				chatType = {
					name = "Target",
					desc = "Chat target",
					type = "select",
					width = "double",
					order = 2,
					values = {
						["SAY"] = "Say",
						["WHISPER"] = "Whisper",
						["YELL"] = "Yell",
						["PARTY"] = "Party",
						["GUILD"] = "Guild",
						["OFFICER"] = "Officer",
						["RAID"] = "Raid",
						["RAID_WARNING"] = "Raid Warning",
						["BATTLEGROUND"] = "Battleground",
						["TARGET"] = "Target",
						["WHISPER"] = "Whisper",
						["REPLY"] = "Reply to whisper",
						["GROUP"] = "Auto determine group",
					},
					set = function(info,val) v.chatType = val end,
					get = function() return v.chatType or "SAY" end,
				},
				category = {
					name = "Category",
					desc = "The category for this message",
					type = "input",
					order = 3,
					set = function(info,val) v.category = val end,
					get = function() return v.category or "General" end,
				},
				content = {
					name = "Content",
					desc = "Content",
					type = "input",
					width = "full",
					order = 3,
					multiline = true,
					set = function(info,val) v.content = val end,
					get = function() return v.content or "" end,
				},
				footer = {
					name = "Other",
					type = "header",
					order = 4,
				},
				test = {
					name = "Test",
					desc = "Click to test this message",
					type = "execute",
					order = 5,
					func = function() AutoText:SayMessage(k) end,
				},
				delete = {
					name = "Delete",
					desc = "Click to delete this message",
					type = "execute",
					order = 5,
					func = function() db.messages[k] = nil end,
				},
			}
		}
	end

	return options
end

function AutoText:ShowConfigDialog()
	LibStub("AceConfigDialog-3.0"):Open("AutoText")
end

function AutoText:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("AutoTextDB", defaults, "Default")
	db = self.db.profile

	LibStub("AceConfig-3.0"):RegisterOptionsTable("AutoText", GetOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("AutoText", "AutoText")
	LibStub("tekKonfig-AboutPanel").new("AutoText", "AutoText")

	self:RegisterChatCommand("autotext", "ShowConfigDialog")
	self:RegisterChatCommand("at", "ShowConfigDialog")
	self:RegisterChatCommand("atsay", "SayMessage")
	self:RegisterChatCommand("atlist", "ListMessages")

	self:RegisterLDBObject()
end

function AutoText:OnEnable()
	--[[ Store the last person to send us a whisper for use in the REPLY pseudo-target ]]
	self:RegisterEvent("CHAT_MSG_WHISPER", function() lastWhisperSentBy = arg2	end)
end


local function strsplit(text,delimiter)
  local list = {}
  local pos = 1
  if strfind("", delimiter, 1) then -- this would result in endless loops
    error("delimiter matches empty string!")
  end
  while 1 do
    local first, last = strfind(text, delimiter, pos)
    if first then -- found?
      tinsert(list, strsub(text, pos, first-1))
      pos = last+1
    else
      tinsert(list, strsub(text, pos))
      break
    end
  end
  return list
end

--[[
-- This function will resolve UnitIDs in messages using the UnitName API call.
-- If a unit doesn't exist it will be replaced with 'Unknown'
-- Thanks to celebros for the patch
--]]
local function ResolveUnits(msg)
	local resolveUnit = function(unit)
		local name = UnitName(unit);
		if name then
			return name;
		else
			return 'Unknown';
		end
	end
	return string.gsub(msg, '${(%w+)}', resolveUnit);
end

local function SplitSendChatMessage(content, chatType, channel)
		local msgs = strsplit(ResolveUnits(content), "\n+")
		for i,msg in ipairs(msgs) do
			if msg and (string.len(msg) > 0) then
				SendChatMessage(msg, chatType, nil, channel)
			end
		end
end

function AutoText:ListMessages()
	self:Print("Registered AutoText Messages:")
	for k,v in pairs(db.messages) do
		self:Print(k .. ": " .. string.sub(v.content,1,32))
	end
end

function AutoText:SayMessage(shortcutName)
	local message = db.messages[shortcutName]
	if (not message) then 
		self:Print("Message " .. shortcutName .. " not found.")
		return 
	end

	local content = message.content
	local chatType = message.chatType
	local channel = nil

	--[[ Convert pseudo-targets into real targets ]]
	if chatType == "TARGET" then
		chatType = "WHISPER"
		channel = UnitName("target")
	elseif chatType == "REPLY" then
		if self.lastWhisperSentBy then
			chatType = "WHISPER"
			channel = self.lastWhisperSentBy
		else
			self:Print("Unable to reply. Nobody has whispered you!")
			return
		end
	elseif chatType == "GROUP" then
		local inInstance, instanceType = IsInInstance()
		if inInstance and instanceType == "pvp" then
			chatType = "BATTLEGROUND"
		elseif GetNumRaidMembers() > 0 then
			chatType = 'RAID'
		elseif GetNumPartyMembers() > 0 then
			chatType = 'PARTY'
		else
			self:Print("Unable to send message. You are not in a group.")
			return
		end
	end

	if chatType == 'WHISPER' and channel == nil then
		--[[ Query the user for the WHISPER target ]]
		StaticPopupDialogs["AUTOTEXT_GET_PLAYER_NAME"] = {
			text = "Send whisper to whom?", button1 = "OK", button2 = "Cancel", hasEditBox = 1,
			OnAccept = function(self)
				local player =  self.editBox:GetText()
				SplitSendChatMessage(content, chatType, player)
			end,
			timeout = 0, whileDead = 1, hideOnEscape = 1
		}
		StaticPopup_Show("AUTOTEXT_GET_PLAYER_NAME");
		return
	else --[[ Send the message ]]
		SplitSendChatMessage(content, chatType, channel)
	end

end

