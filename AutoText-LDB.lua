--[[
Name: AutoText\AutoText-LDB.lua
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

if not AutoText then return end

local tooltip
local QTC = LibStub("LibQTip-1.0")

function AutoText:RegisterLDBObject()
	local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
	if not ldb then return end

	local dataobj = ldb:NewDataObject("AutoText", {
		type = "launcher",
		icon = [[Interface\AddOns\AutoText\Icon]],
		text = self.title or self.name or "AutoText",
	})

	dataobj.OnClick = function(frame, button)
		AutoText:ShowConfigDialog()
	end

	dataobj.OnEnter = function(frame)
		tooltip = QTC:Acquire("AutoTextTooltip", 2, "LEFT", "RIGHT")
		tooltip:SmartAnchorTo(frame)
		tooltip:SetAutoHideDelay(0.25, frame)

		local font = GameTooltipHeaderText
		font:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
		tooltip:SetHeaderFont(font)
		tooltip:SetFont(GameTooltipText)
		tooltip:Clear()

		local tabletCategories = {}
		local db = AutoText.db.profile

		-- Group up the messages into categories
		for k,message in pairs(db.messages) do
			-- In case we have old messages without a category, fix em up now
			if message.category == nil or message.category == "" then message.category = "General" end
			-- Create the category bucket if needed
			if (not tabletCategories[message.category]) then tabletCategories[message.category] = {} end
			-- Add the message to the category
			tabletCategories[message.category][k] = message
		end

		-- Build up the tooltip from the categories
		for cat, messages in pairs(tabletCategories) do
			tooltip:AddHeader(cat)
			for k,msg in pairs(messages) do
				local y,x = tooltip:AddLine(msg.name, msg.chatType)

				local msgid = k
				tooltip:SetLineScript(y, "OnMouseDown", function(self, button)
					AutoText:SayMessage(msgid)
				end)
			end
			-- tooltip:AddLine()
		end

		tooltip:Show()
	end

	dataobj.OnLeave = function() 
	end
end

