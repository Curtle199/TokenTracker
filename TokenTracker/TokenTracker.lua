local ADDON_NAME = ...
local TT = CreateFrame("Frame")

local mainFrame
local miniFrame
local statusText
local historyRows = {}

local MAX_HISTORY_ROWS = 8

local function EnsureDB()
    TokenTrackerDB = TokenTrackerDB or {}
    TokenTrackerDB.settings = TokenTrackerDB.settings or {
        miniVisible = true,
        lastAlertKey = "",
        alertsEnabled = true,
        soundEnabled = true,
    }
end

local function GetExternal()
    TokenTrackerExternalDB = TokenTrackerExternalDB or {
        source = "No external data",
        region = "US",
        updatedAt = "-",
        currentPriceGold = 0,
        history = {},
        analytics = {
            avg24 = 0,
            low24 = 0,
            high24 = 0,
            trend = "unknown",
            bestBuyWindow = {
                low = 0,
                high = 0,
                verdict = "No data",
            },
        },
    }
    return TokenTrackerExternalDB
end

local function FormatGold(gold)
    gold = tonumber(gold) or 0
    return string.format("%.0f g", gold)
end

local function SetStatus(msg, r, g, b)
    if not statusText then
        return
    end
    statusText:SetText(msg or "")
    statusText:SetTextColor(r or 1, g or 0.82, b or 0.2)
end

local function MakeLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function MakeValue(parent, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetText("-")
    return fs
end

local function GetTimeAgo(timestamp)
    if not timestamp or timestamp == "-" then
        return "No data"
    end

    local year, month, day, hour, min, sec =
        timestamp:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")

    if not year then
        return "Invalid time"
    end

    local t = time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })

    local diff = time() - t

    if diff < 60 then
        return "Updated just now"
    elseif diff < 3600 then
        return "Updated " .. math.floor(diff / 60) .. " min ago"
    elseif diff < 86400 then
        return "Updated " .. math.floor(diff / 3600) .. " hr ago"
    else
        return "Updated " .. math.floor(diff / 86400) .. "d ago"
    end
end

local function GetDeltaInfo()
    local ext = GetExternal()
    local history = ext.history or {}
    local current = tonumber(ext.currentPriceGold) or 0

    if #history < 2 then
        return "-", 1, 1, 1
    end

    local oldestVisible = tonumber(history[#history].priceGold) or 0
    if oldestVisible <= 0 then
        return "-", 1, 1, 1
    end

    local diff = current - oldestVisible
    local pct = (diff / oldestVisible) * 100
    local prefix = diff > 0 and "+" or ""

    local text = string.format("%s%d g (%.2f%%)", prefix, diff, pct)

    if diff > 0 then
        return text, 0.2, 1, 0.2
    elseif diff < 0 then
        return text, 1, 0.4, 0.4
    else
        return text, 1, 0.82, 0.2
    end
end

local function GetVsAverageInfo()
    local ext = GetExternal()
    local analytics = ext.analytics or {}

    local current = tonumber(ext.currentPriceGold) or 0
    local avg = tonumber(analytics.avg24) or 0

    if current <= 0 or avg <= 0 then
        return "-", 1, 1, 1
    end

    local diff = current - avg
    local pct = (diff / avg) * 100
    local prefix = diff > 0 and "+" or ""

    local text = string.format("%s%d g (%.2f%%)", prefix, diff, pct)

    if diff > 0 then
        return text, 1, 0.4, 0.4
    elseif diff < 0 then
        return text, 0.2, 1, 0.2
    else
        return text, 1, 0.82, 0.2
    end
end

local function GetMiniTrendSummary()
    local ext = GetExternal()
    local history = ext.history or {}

    if #history < 2 then
        return "Not enough data", 0.8, 0.8, 0.8
    end

    local newest = tonumber(history[1].priceGold) or 0
    local oldest = tonumber(history[#history].priceGold) or 0
    local diff = newest - oldest

    if diff < 0 then
        return "Down over recent samples", 1, 0.4, 0.4
    elseif diff > 0 then
        return "Up over recent samples", 0.2, 1, 0.2
    else
        return "Flat over recent samples", 1, 0.82, 0.2
    end
end

local function GetUndervaluedScore()
    local ext = GetExternal()
    local a = ext.analytics or {}

    local current = tonumber(ext.currentPriceGold) or 0
    local avg = tonumber(a.avg24) or 0
    local low = tonumber(a.low24) or 0
    local trend = tostring(a.trend or "unknown")

    if current <= 0 or avg <= 0 or low <= 0 then
        return 0, "No data", 0.8, 0.8, 0.8
    end

    local score = 50

    local pctVsAvg = ((avg - current) / avg) * 100
    if pctVsAvg > 0 then
        score = score + math.min(25, pctVsAvg * 4)
    else
        score = score + math.max(-25, pctVsAvg * 3)
    end

    local pctAboveLow = ((current - low) / low) * 100
    if pctAboveLow <= 1 then
        score = score + 20
    elseif pctAboveLow <= 3 then
        score = score + 10
    elseif pctAboveLow >= 8 then
        score = score - 10
    end

    if trend == "falling" then
        score = score - 10
    elseif trend == "rising" then
        score = score + 5
    end

    score = math.max(0, math.min(100, math.floor(score + 0.5)))

    if score >= 80 then
        return score, "Undervalued", 0.2, 1, 0.2
    elseif score >= 60 then
        return score, "Interesting", 1, 0.82, 0.2
    else
        return score, "Weak", 1, 0.4, 0.4
    end
end

local function GetSmartBuyWindow()
    local ext = GetExternal()
    local a = ext.analytics or {}

    local avg = tonumber(a.avg24) or 0
    local low = tonumber(a.low24) or 0
    local current = tonumber(ext.currentPriceGold) or 0
    local trend = tostring(a.trend or "unknown")

    if avg <= 0 or low <= 0 or current <= 0 then
        return 0, 0, "No data"
    end

    local gap = math.max(1, avg - low)
    local factor = 0.35

    if trend == "falling" then
        factor = 0.22
    elseif trend == "rising" then
        factor = 0.50
    elseif trend == "flat" then
        factor = 0.35
    end

    local windowLow = low
    local windowHigh = math.floor(low + (gap * factor))

    if windowHigh < windowLow then
        windowHigh = windowLow
    end

    local verdict
    if current <= windowHigh then
        if current <= low * 1.01 then
            verdict = "STRONG BUY"
        else
            verdict = "BUY"
        end
    elseif current <= avg then
        verdict = "WAIT"
    else
        verdict = "AVOID"
    end

    return windowLow, windowHigh, verdict
end

local function MaybeFireAlert(verdict, current, low, high)
    local settings = TokenTrackerDB.settings
    if not settings.alertsEnabled then
        return
    end

    local key = tostring(verdict) .. "|" .. tostring(current) .. "|" .. tostring(low) .. "|" .. tostring(high)

    if verdict == "STRONG BUY" or verdict == "BUY" then
        if settings.lastAlertKey ~= key then
            settings.lastAlertKey = key
            print("|cff00ff00TokenTracker: " .. verdict .. " window hit at " .. FormatGold(current) .. ".|r")
            if settings.soundEnabled then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
        end
    else
        settings.lastAlertKey = ""
    end
end

local function RefreshHistory()
    local ext = GetExternal()

    for i = 1, MAX_HISTORY_ROWS do
        local row = historyRows[i]
        local entry = ext.history[i]

        if entry then
            row:Show()
            row.time:SetText(entry.time or "-")
            row.price:SetText(FormatGold(entry.priceGold))
        else
            row:Hide()
        end
    end
end

local function RefreshMiniFrame()
    if not miniFrame then
        return
    end

    local ext = GetExternal()
    local a = ext.analytics or {}
    local windowLow, windowHigh, verdict = GetSmartBuyWindow()

    local trend = tostring(a.trend or "unknown")
    local arrow = "-"
    local tr, tg, tb = 1, 0.82, 0.2

    if trend == "falling" then
        arrow = "v"
        tr, tg, tb = 1, 0.4, 0.4
    elseif trend == "rising" then
        arrow = "^"
        tr, tg, tb = 0.2, 1, 0.2
    elseif trend == "flat" then
        arrow = "-"
    end

    miniFrame.priceValue:SetText(FormatGold(ext.currentPriceGold or 0))
    miniFrame.trendValue:SetText(arrow .. " " .. trend)
    miniFrame.trendValue:SetTextColor(tr, tg, tb)

    miniFrame.callValue:SetText(verdict)
    if verdict == "STRONG BUY" or verdict == "BUY" then
        miniFrame.callValue:SetTextColor(0.2, 1, 0.2)
    elseif verdict == "WAIT" then
        miniFrame.callValue:SetTextColor(1, 0.82, 0.2)
    else
        miniFrame.callValue:SetTextColor(1, 0.4, 0.4)
    end

    if TokenTrackerDB.settings.miniVisible then
        miniFrame:Show()
    else
        miniFrame:Hide()
    end

    MaybeFireAlert(verdict, tonumber(ext.currentPriceGold) or 0, windowLow, windowHigh)
end

local function RefreshUI()
    local ext = GetExternal()
    local analytics = ext.analytics or {}

    local windowLow, windowHigh, verdict = GetSmartBuyWindow()

    mainFrame.sourceValue:SetText((ext.source or "-") .. " / " .. (ext.region or "-"))

    local timeAgo = GetTimeAgo(ext.updatedAt)
    if ext.updatedAt and ext.updatedAt ~= "-" then
        mainFrame.updatedValue:SetText(timeAgo .. " (" .. ext.updatedAt .. ")")
    else
        mainFrame.updatedValue:SetText(timeAgo)
    end

    mainFrame.currentValue:SetText(ext.currentPriceGold and FormatGold(ext.currentPriceGold) or "-")
    mainFrame.avgValue:SetText(analytics.avg24 and FormatGold(analytics.avg24) or "-")
    mainFrame.lowValue:SetText(analytics.low24 and FormatGold(analytics.low24) or "-")
    mainFrame.highValue:SetText(analytics.high24 and FormatGold(analytics.high24) or "-")
    mainFrame.trendValue:SetText(analytics.trend or "-")

    if windowLow > 0 and windowHigh > 0 then
        mainFrame.windowValue:SetText(FormatGold(windowLow) .. " - " .. FormatGold(windowHigh))
    else
        mainFrame.windowValue:SetText("-")
    end

    mainFrame.callValue:SetText(verdict)

    if verdict == "STRONG BUY" or verdict == "BUY" then
        mainFrame.callValue:SetTextColor(0.2, 1, 0.2)
        SetStatus("Price is in or near the buy window.", 0.2, 1, 0.2)
    elseif verdict == "WAIT" then
        mainFrame.callValue:SetTextColor(1, 0.82, 0.2)
        SetStatus("Price is outside the buy window.", 1, 0.82, 0.2)
    else
        mainFrame.callValue:SetTextColor(1, 0.4, 0.4)
        SetStatus("No strong signal yet.", 1, 0.4, 0.4)
    end

    local deltaText, dr, dg, db = GetDeltaInfo()
    mainFrame.deltaValue:SetText(deltaText)
    mainFrame.deltaValue:SetTextColor(dr, dg, db)

    local avgText, ar, ag, ab = GetVsAverageInfo()
    mainFrame.avgDiffValue:SetText(avgText)
    mainFrame.avgDiffValue:SetTextColor(ar, ag, ab)

    local trendSummary, tr, tg, tb = GetMiniTrendSummary()
    mainFrame.trendSummaryValue:SetText(trendSummary)
    mainFrame.trendSummaryValue:SetTextColor(tr, tg, tb)

    local score, scoreLabel, sr, sg, sb = GetUndervaluedScore()
    mainFrame.scoreValue:SetText(score .. "/100 - " .. scoreLabel)
    mainFrame.scoreValue:SetTextColor(sr, sg, sb)

    RefreshHistory()
    RefreshMiniFrame()
    MaybeFireAlert(verdict, tonumber(ext.currentPriceGold) or 0, windowLow, windowHigh)
end

local function CreateHistoryRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(220, 20)
    row:SetPoint("TOPLEFT", 20, -455 - ((index - 1) * 22))

    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.time:SetPoint("LEFT", 0, 0)
    row.time:SetWidth(100)
    row.time:SetJustifyH("LEFT")

    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.price:SetPoint("LEFT", 110, 0)
    row.price:SetWidth(100)
    row.price:SetJustifyH("LEFT")

    return row
end

local function CreateMiniTrendPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(320, 220)
    panel:SetPoint("TOPLEFT", 190, -285)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.18)

    local borderTop = panel:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT")
    borderTop:SetPoint("TOPRIGHT")
    borderTop:SetHeight(1)
    borderTop:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    local borderBottom = panel:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT")
    borderBottom:SetPoint("BOTTOMRIGHT")
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    local borderLeft = panel:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT")
    borderLeft:SetPoint("BOTTOMLEFT")
    borderLeft:SetWidth(1)
    borderLeft:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    local borderRight = panel:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT")
    borderRight:SetPoint("BOTTOMRIGHT")
    borderRight:SetWidth(1)
    borderRight:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    MakeLabel(parent, "Mini Trend Panel", 190, -275)

    MakeLabel(parent, "Change vs Oldest Visible", 205, -305)
    mainFrame.deltaValue = MakeValue(parent, 205, -325, 260)

    MakeLabel(parent, "Difference vs 24h Avg", 205, -350)
    mainFrame.avgDiffValue = MakeValue(parent, 205, -370, 260)

    MakeLabel(parent, "Recent Direction", 205, -395)
    mainFrame.trendSummaryValue = MakeValue(parent, 205, -415, 260)

    MakeLabel(parent, "Undervalued Score", 205, -440)
    mainFrame.scoreValue = MakeValue(parent, 205, -460, 260)
end

local function CreateMiniFrame()
    miniFrame = CreateFrame("Frame", "TokenTrackerMiniFrame", UIParent, "BasicFrameTemplateWithInset")
    miniFrame:SetSize(180, 110)
    miniFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -140)
    miniFrame:SetMovable(true)
    miniFrame:EnableMouse(true)
    miniFrame:RegisterForDrag("LeftButton")
    miniFrame:SetScript("OnDragStart", miniFrame.StartMoving)
    miniFrame:SetScript("OnDragStop", miniFrame.StopMovingOrSizing)

    miniFrame.title = miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    miniFrame.title:SetPoint("LEFT", miniFrame.TitleBg, "LEFT", 5, 0)
    miniFrame.title:SetText("Token Mini")

    miniFrame.priceValue = MakeValue(miniFrame, 12, -30, 150)
    miniFrame.trendValue = MakeValue(miniFrame, 12, -52, 150)
    miniFrame.callValue = MakeValue(miniFrame, 12, -74, 150)
end

local function CreateUI()
    mainFrame = CreateFrame("Frame", "TokenTrackerMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(540, 720)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:Hide()

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Token Tracker")

    local refreshBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(120, 24)
    refreshBtn:SetPoint("TOPRIGHT", -40, -40)
    refreshBtn:SetText("Refresh View")
    refreshBtn:SetScript("OnClick", RefreshUI)

    local miniBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    miniBtn:SetSize(120, 24)
    miniBtn:SetPoint("TOPRIGHT", -170, -40)
    miniBtn:SetText("Toggle Mini")
    miniBtn:SetScript("OnClick", function()
        TokenTrackerDB.settings.miniVisible = not TokenTrackerDB.settings.miniVisible
        RefreshMiniFrame()
    end)

    MakeLabel(mainFrame, "Source", 20, -40)
    mainFrame.sourceValue = MakeValue(mainFrame, 20, -60, 220)

    MakeLabel(mainFrame, "Last Updated", 280, -40)
    mainFrame.updatedValue = MakeValue(mainFrame, 280, -60, 230)

    MakeLabel(mainFrame, "Current", 20, -110)
    mainFrame.currentValue = MakeValue(mainFrame, 20, -130, 140)

    MakeLabel(mainFrame, "24h Avg", 20, -155)
    mainFrame.avgValue = MakeValue(mainFrame, 20, -175, 140)

    MakeLabel(mainFrame, "24h Low", 20, -200)
    mainFrame.lowValue = MakeValue(mainFrame, 20, -220, 140)

    MakeLabel(mainFrame, "24h High", 20, -245)
    mainFrame.highValue = MakeValue(mainFrame, 20, -265, 140)

    MakeLabel(mainFrame, "Trend", 190, -110)
    mainFrame.trendValue = MakeValue(mainFrame, 190, -130, 140)

    MakeLabel(mainFrame, "Best Buy Window", 190, -155)
    mainFrame.windowValue = MakeValue(mainFrame, 190, -175, 220)

    MakeLabel(mainFrame, "Call", 190, -210)
    mainFrame.callValue = MakeValue(mainFrame, 190, -230, 220)

    CreateMiniTrendPanel(mainFrame)

    MakeLabel(mainFrame, "Recent Imported History", 20, -430)

    local headerTime = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTime:SetPoint("TOPLEFT", 20, -450)
    headerTime:SetText("Time")

    local headerPrice = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerPrice:SetPoint("TOPLEFT", 130, -450)
    headerPrice:SetText("Price")

    for i = 1, MAX_HISTORY_ROWS do
        historyRows[i] = CreateHistoryRow(mainFrame, i)
    end

    statusText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 20, 20)
    statusText:SetWidth(490)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Waiting for imported data.")

    CreateMiniFrame()
end

TT:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            EnsureDB()
            CreateUI()
        end
    elseif event == "PLAYER_LOGIN" then
        SLASH_TOKENTRACKER1 = "/tt"
        SlashCmdList["TOKENTRACKER"] = function()
            if mainFrame:IsShown() then
                mainFrame:Hide()
            else
                mainFrame:Show()
                RefreshUI()
            end
        end

        SLASH_TOKENTRACKERMINI1 = "/ttmini"
        SlashCmdList["TOKENTRACKERMINI"] = function()
            TokenTrackerDB.settings.miniVisible = not TokenTrackerDB.settings.miniVisible
            RefreshMiniFrame()
        end

        if TokenTrackerDB.settings.miniVisible then
            miniFrame:Show()
        else
            miniFrame:Hide()
        end
    end
end)

TT:RegisterEvent("ADDON_LOADED")
TT:RegisterEvent("PLAYER_LOGIN")