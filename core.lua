Forged_Mailbox = Forged_Mailbox or {}
L = Forged_Mailbox.L

if not L then
  L = setmetatable({
    date_format = "%d.%m.%Y",
    time_format = "%H:%M",
  }, { __index = function( _, k ) return k end })
end

local m = Forged_Mailbox
local getn = table.getn ---@diagnostic disable-line: deprecated

-- Use the true global environment so SavedVariables persist across /reload.
Forged_Mailbox.api = getfenv(0)
Forged_Mailbox.timer = 0
Forged_Mailbox.log = {}
Forged_Mailbox.ledger = Forged_Mailbox.ledger or {}
Forged_Mailbox.orig = {}
Forged_Mailbox.hooks = {}
Forged_Mailbox.hook = setmetatable( {}, { __newindex = function( _, k, v ) m.hooks[ k ] = v end } )
Forged_Mailbox.debug_enabled = false

function Forged_Mailbox.hook.MailFrameTab_OnClick( tab )
  if not tab then
    tab = this:GetID()
  end

  if tab == 3 or tab == 4 then
    m.api.PanelTemplates_SetTab( m.api.MailFrame, tab )
    m.api.InboxFrame:Hide()
    m.api.SendMailFrame:Hide()

    if m.api.Forged_MailboxLogFrame then m.api.Forged_MailboxLogFrame:Hide() end
    if m.api.Forged_MailboxLedgerFrame then m.api.Forged_MailboxLedgerFrame:Hide() end

    if tab == 3 then
      if m.api.Forged_MailboxLedgerFrame then
        m.api.Forged_MailboxLedgerFrame:Show()
      end
      if m.ledger and m.ledger.populate then
        m.ledger.populate()
      end
    else
      if m.api.Forged_MailboxLogFrame then
        m.api.Forged_MailboxLogFrame:Show()
      end
      if m.log and m.log.populate then
        m.log.populate( "Received" )
      end
    end

    m.api.MailFrameTopLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopLeft" )
    m.api.MailFrameTopRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopRight" )
    m.api.MailFrameBotLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotLeft" )
    m.api.MailFrameBotRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotRight" )
    m.api.MailFrameTopLeft:SetPoint( "TOPLEFT", "MailFrame", "TOPLEFT", 2, -1 )
    return
  end

  if m.api.Forged_MailboxLogFrame then m.api.Forged_MailboxLogFrame:Hide() end
  if m.api.Forged_MailboxLedgerFrame then m.api.Forged_MailboxLedgerFrame:Hide() end
  m.orig.MailFrameTab_OnClick( tab )
end

do
  local picker = m.date_picker or m.Calendar
  if picker and picker.new then
    Forged_Mailbox.calendar = picker.new()
  else
    -- Keep addon functional even if date picker fails to load.
    Forged_Mailbox.calendar = {
      show = function() end,
      hide = function() end,
      is_visible = function() return false end,
    }
  end
end

function Forged_Mailbox.ensure_savedvars()
  -- Migrate old savedvar names (pre-rename) to new ones.
  if m.api.ForgedMailboxLogCharDB and not m.api.ForgedMailboxLogDB then
    m.api.ForgedMailboxLogDB = m.api.ForgedMailboxLogCharDB
  end
  if m.api.Forged_Mailbox_Log and not m.api.ForgedMailboxLogDB then
    m.api.ForgedMailboxLogDB = m.api.Forged_Mailbox_Log
  end
  if m.api.Forged_Mailbox_AutoCompleteNames and not m.api.ForgedMailboxDB then
    m.api.ForgedMailboxDB = m.api.Forged_Mailbox_AutoCompleteNames
  end

  m.api.ForgedMailboxLogDB = m.api.ForgedMailboxLogDB or {}
  m.api.ForgedMailboxLogDB.Sent = m.api.ForgedMailboxLogDB.Sent or {}
  m.api.ForgedMailboxLogDB.Received = m.api.ForgedMailboxLogDB.Received or {}
  m.api.ForgedMailboxLogDB.Settings = m.api.ForgedMailboxLogDB.Settings or {}

  m.api.ForgedMailboxLedgerDB = m.api.ForgedMailboxLedgerDB or {}
  m.api.ForgedMailboxLedgerDB.Sent = m.api.ForgedMailboxLedgerDB.Sent or {}
  m.api.ForgedMailboxLedgerDB.Received = m.api.ForgedMailboxLedgerDB.Received or {}
  m.api.ForgedMailboxLedgerDB.Settings = m.api.ForgedMailboxLedgerDB.Settings or {}
  m.api.ForgedMailboxLedgerDB.Daily = m.api.ForgedMailboxLedgerDB.Daily or {}

  local settings = m.api.ForgedMailboxLogDB.Settings
  if settings.Enabled == nil then settings.Enabled = false end
  settings.SentFilters = settings.SentFilters or { Money = 1, COD = 1, Other = 1 }
  settings.ReceivedFilters = settings.ReceivedFilters
      or { Money = 1, COD = 1, Other = 1, Returned = 1, AH = 1, AHSold = 1, AHOutbid = 1, AHWon = 1, AHCancelled = 1, AHExpired = 1 }

  local ledger_settings = m.api.ForgedMailboxLedgerDB.Settings
  -- Ledger is always enabled and must not be controlled by /fmb log.
  ledger_settings.Enabled = true
  ledger_settings.SentFilters = ledger_settings.SentFilters or { Money = 1, COD = 1, Other = 1 }
  ledger_settings.ReceivedFilters = ledger_settings.ReceivedFilters
      or { Money = 1, COD = 1, Other = 1, Returned = 1, AH = 1, AHSold = 1, AHOutbid = 1, AHWon = 1, AHCancelled = 1, AHExpired = 1 }

  -- Period filters are session-only and reset when opening the mailbox.

  m.api.ForgedMailboxDB = m.api.ForgedMailboxDB or {}
end

function Forged_Mailbox:init()
  self.debug( "Forged_Mailbox.init" )
  self.update_frame = m.api.CreateFrame( "Frame", "Forged_MailboxFrame", m.api.MailFrame )
  self.update_frame:SetScript( "OnUpdate", self.on_update )

  -- Register events
  self.update_frame:SetScript( "OnEvent", function() self[ event ]() end )
  for _, ev in ipairs( { "ADDON_LOADED", "PLAYER_LOGIN", "UI_ERROR_MESSAGE", "CURSOR_UPDATE", "BAG_UPDATE", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_INBOX_UPDATE" } ) do
    self.update_frame:RegisterEvent( ev )
  end

  self.ensure_savedvars()

  -- hack to prevent beancounter from deleting mail
  self.TakeInboxMoney, self.TakeInboxItem, self.DeleteInboxItem = m.api.TakeInboxMoney, m.api.TakeInboxItem, m.api.DeleteInboxItem

  self.tooltip_frame = m.api.CreateFrame( "GameTooltip", "Forged_MailboxTooltipFrame", nil, "GameTooltipTemplate" )
  self.tooltip_frame:SetOwner( m.api.WorldFrame, "ANCHOR_NONE" )
end

---@param args string
function Forged_Mailbox.slash_command( args )
  m.ensure_savedvars()
  if args == "" or args == "help" then
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473Forged_Mailbox Help|r" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm log|r Toggle Log tab on/off" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear sent|r Clear sent log" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear received|r Clear received log" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear names|r Clear saved recipient names from autocomplete" )
    return
  end

  if args == "log" then
    local enabled = not m.api.ForgedMailboxLogDB[ "Settings" ][ "Enabled" ]
    m.api.ForgedMailboxLogDB[ "Settings" ][ "Enabled" ] = enabled
    if enabled then
      m.info( "Logging is enabled." )
      if m.api.MailFrame:IsVisible() then
        if m.api.MailFrameTab4 then m.api.MailFrameTab4:Show() end
      end
    else
      m.info( "Logging is disabled." )
      if m.api.MailFrame:IsVisible() then
        if m.api.MailFrameTab4 then m.api.MailFrameTab4:Hide() end
      end
    end
    m.log_enabled = enabled
  end

  if string.find( args, "^clear" ) then
    if args == "clear sent" then
      m.info( "Sent log cleared." )
      m.api.ForgedMailboxLogDB[ "Sent" ] = {}
    elseif args == "clear received" then
      m.info( "Received log cleared." )
      m.api.ForgedMailboxLogDB[ "Received" ] = {}
    elseif args == "clear names" then
      m.info( "Recipient autocomplete names have been cleared." )
      local key = m.api.GetCVar( "realmName" ) .. "|" .. m.api.UnitFactionGroup( "player" )
      m.api.ForgedMailboxDB[ key ] = {}
    end
  end

  if args == "debug" then
    m.debug_enabled = not m.debug_enabled
    if m.debug_enabled then
      m.info( "Debug is enabled." )
    else
      m.info( "Debug is disabled." )
    end
  end
end

function Forged_Mailbox.on_update()
  if not m.api.MailFrame or not m.api.MailFrame:IsVisible() then return end

  if m._cursorItem then
    m.debug( "on_update: cursorItem" )
    m.cursorItem = m._cursorItem
    m._cursorItem = nil
  end

  if m.sendmail_update then
    m.debug( "on_update: sendmail" )
    m.sendmail_update = nil
    if m.sendmail_sending then
      m.debug( "m.sendmail_sending" )
      m.sendmail_send()
    end
  end

  if m.inbox_update then
    m.debug( "on_update: inbox_update" )
    m.inbox_update = false
    local _, _, sender, subject, _, COD, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( m.inbox_index )
    if m.inbox_index > m.api.GetInboxNumItems() then
      m.inbox_abort()
    elseif m.inbox_open_filter == "auction"
        and m.inbox_is_auction_mail
        and (not m.inbox_is_auction_mail( sender, subject )) then
      m.inbox_index = m.inbox_index + 1
      m.inbox_update = true
    elseif m.inbox_skip or COD > 0 or isGM then
      m.inbox_skip = false
      m.inbox_index = m.inbox_index + 1
      m.inbox_update = true
    else
      m.inbox_open( m.inbox_index )
    end
  end

  if m.timer > 0 then
    m.timer = m.timer - 1
  elseif not m.inbox_opening then
    m.timer = 200
    m.api.CheckInbox()
  end
end

function Forged_Mailbox.CURSOR_UPDATE()
  m.cursorItem = nil
end

function Forged_Mailbox.get_cursor_item()
  return m.cursorItem
end

---@param item table
function Forged_Mailbox.set_cursor_item( item )
  m._cursorItem = item
end

function Forged_Mailbox.BAG_UPDATE()
  if m.api.MailFrame:IsVisible() then
    m.api.SendMailFrame_Update()
  end
end

function Forged_Mailbox.MAIL_SHOW()
  -- Removed Forged_Mailbox_Point functionality

  if not m.first_show then
    m.first_show = true
    local background = ({ m.api.SendMailPackageButton:GetRegions() })[ 1 ]
    background:Hide()
    local count = ({ m.api.SendMailPackageButton:GetRegions() })[ 3 ]
    count:Hide()
    m.api.SendMailPackageButton:Disable()
    m.api.SendMailPackageButton:SetScript( "OnReceiveDrag", nil )
    m.api.SendMailPackageButton:SetScript( "OnDragStart", nil )
  end

  -- Ledger tab is always visible.
  if m.api.MailFrameTab3 then
    m.api.MailFrameTab3:Show()
  end

  -- Log tab is controlled by logging toggle.
  if m.api.MailFrameTab4 then
    if m.log_enabled then
      m.api.MailFrameTab4:Show()
    else
      m.api.MailFrameTab4:Hide()
    end
  end

  m.timer = 0

  -- Default Log/Ledger period: last 30 days (no SavedVariables persistence).
  if m.ledger and m.ledger.set_default_period then
    m.ledger.set_default_period()
  end
  if m.log and m.log.set_default_period then
    m.log.set_default_period()
  end
end

function Forged_Mailbox.MAIL_CLOSED()
  m.inbox_abort()
  m.sendmail_sending = false
  m.sendmail_clear()
end

function Forged_Mailbox.UI_ERROR_MESSAGE()
  if m.inbox_opening then
    if arg1 == m.api.ERR_INV_FULL then
      m.inbox_abort()
    elseif arg1 == m.api.ERR_ITEM_MAX_COUNT then
      m.inbox_skip = true
    end
  elseif m.sendmail_sending
      and (arg1 == m.api.ERR_MAIL_TO_SELF or arg1 == m.api.ERR_PLAYER_WRONG_FACTION or arg1 == m.api.ERR_MAIL_TARGET_NOT_FOUND or arg1 == m.api.ERR_MAIL_REACHED_CAP) then
    m.sendmail_sending = false
    m.sendmail_state = nil
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
  end
end

function Forged_Mailbox.ADDON_LOADED()
  if arg1 ~= "Forged_Mailbox" then return end

  m.ensure_savedvars()

  local version = m.api.GetAddOnMetadata( "Forged_Mailbox", "Version" )
  m.info( string.format( "Loaded (|cffeda55fv%s|r).", version ) )

  if m.debug_enabled then
    m.info( "Expected files: date_picker.lua, core.lua, open_mail.lua, send_mail.lua, autocomplete.lua, log.lua, ledger.lua" )
  end

  if not m.api.ForgedMailboxLogDB[ "Settings" ].first_run then
    m.api.ForgedMailboxLogDB[ "Settings" ].first_run = version
    m.info( "New in |cffeda55fv1.4|r: Toggle Log with |cffabd473/tm log|r" )
  end

  if m.api.UIPanelWindows[ "MailFrame" ] then
    m.api.UIPanelWindows[ "MailFrame" ].pushable = 1
  else
    m.api.UIPanelWindows[ "MailFrame" ] = { area = "left", pushable = 1 }
  end

  if m.api.UIPanelWindows[ "FriendsFrame" ] then
    m.api.UIPanelWindows[ "FriendsFrame" ].pushable = 2
  else
    m.api.UIPanelWindows[ "FriendsFrame" ] = { area = "left", pushable = 2 }
  end

  m.api.MailFrame:SetScript( "OnDragStop", m.on_drag_stop )
  m.api.MailFrame:SetClampedToScreen( true )
  m.api.PanelTemplates_SetNumTabs( m.api.MailFrame, 4 )

  local function call_or_warn( label, fn )
    if type( fn ) == "function" then
      return fn()
    end

    if m.api and m.api.DEFAULT_CHAT_FRAME and m.api.DEFAULT_CHAT_FRAME.AddMessage then
      m.api.DEFAULT_CHAT_FRAME:AddMessage(
        string.format(
          "|cffff0000Forged_Mailbox|r: Missing module entrypoint '%s'. Check that the file is listed in Forged_Mailbox.toc and restart the client (TOC changes don't always apply to /reload).",
          tostring( label )
        )
      )
    end
  end

  -- Feature module entrypoints (loaded via .toc)
  call_or_warn( "inbox_load", m.inbox_load )
  call_or_warn( "sendmail_load", m.sendmail_load )
  call_or_warn( "log.load", m.log and m.log.load )
  call_or_warn( "ledger.load", m.ledger and m.ledger.load )
end

function Forged_Mailbox.PLAYER_LOGIN()
  m.ensure_savedvars()
  m.debug( "PLAYER_LOGIN" )

  for k, v in pairs( m.hooks ) do
    m.orig[ k ] = m.api[ k ]
    m.api[ k ] = v
  end

  local key = m.api.GetCVar( "realmName" ) .. "|" .. m.api.UnitFactionGroup( "player" )
  m.api.ForgedMailboxDB[ key ] = m.api.ForgedMailboxDB[ key ] or {}
  for char, last_seen in pairs( m.api.ForgedMailboxDB[ key ] ) do
    if m.api.GetTime() - last_seen > 60 * 60 * 24 * 30 then
      m.api.ForgedMailboxDB[ key ][ char ] = nil
    end
  end

  m.add_auto_complete_name( m.api.UnitName( "player" ) )
  m.log_enabled = m.api.ForgedMailboxLogDB[ "Settings" ][ "Enabled" ]

  SLASH_FORGEDMAILBOX1 = "/forgedmailbox"
  SLASH_FORGEDMAILBOX2 = "/fmb"
  m.api.SlashCmdList[ "FORGEDMAILBOX" ] = m.slash_command
end

function Forged_Mailbox.MAIL_SEND_SUCCESS()
  m.debug( "MAIL_SEND_SUCCESS" )
  if m.sendmail_state and not m.sendmail_state.sent then
    m.sendmail_state.sent = true
    if m.log and m.log.add then m.log.add( "Sent", m.sendmail_state ) end
    m.add_auto_complete_name( m.sendmail_state.to )
  end
  if m.sendmail_sending then
    m.sendmail_update = true
  end
end

---@param name string
function Forged_Mailbox.add_auto_complete_name( name )
  local key = m.api.GetCVar( "realmName" ) .. "|" .. m.api.UnitFactionGroup( "player" )
  m.api.ForgedMailboxDB[ key ] = m.api.ForgedMailboxDB[ key ] or {}
  m.api.ForgedMailboxDB[ key ][ name ] = m.api.GetTime()
end

---@param copper number
function Forged_Mailbox.format_money( copper )
  if type( copper ) ~= "number" then return "-" end

  local gold = math.floor( copper / 10000 )
  local silver = math.floor( (copper - gold * 10000) / 100 )
  local copper_remain = copper - (gold * 10000) - (silver * 100)

  local result = ""
  if gold > 0 then
    result = result .. string.format( "|cffffffff%d|cffffd700g|r ", gold )
  end
  if silver > 0 then
    result = result .. string.format( "|cffffffff%d|cffc7c7cfs|r ", silver )
  end
  if copper_remain > 0 or result == "" then
    result = result .. string.format( "|cffffffff%d|cffeda55fc|r ", copper_remain )
  end

  return result
end

function Forged_Mailbox.on_drag_stop()
  this:StopMovingOrSizing()
  local point, _, _, x, y = m.api.MailFrame:GetPoint()
  -- Removed Forged_Mailbox_Point functionality
end

function Forged_Mailbox.filter( t, f, extract_field )
  if not t then return nil end
  if type( f ) ~= "function" then return t end

  local result = {}

  for i = 1, getn( t ) do
    local v = t[ i ]
    local value = type( v ) == "table" and extract_field and v[ extract_field ] or v
    if f( value ) then table.insert( result, v ) end
  end

  return result
end

function Forged_Mailbox.info( message )
  m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473Forged_Mailbox|r: %s", message ) )
end

function Forged_Mailbox.dump( o )
  if not o then return "nil" end
  if type( o ) ~= 'table' then return tostring( o ) end

  local entries = 0
  local s = "{"

  for k, v in pairs( o ) do
    if (entries == 0) then s = s .. " " end
    local key = type( k ) ~= "number" and '"' .. k .. '"' or k
    if (entries > 0) then s = s .. ", " end
    s = s .. "[" .. key .. "] = " .. m.dump( v )
    entries = entries + 1
  end

  if (entries > 0) then s = s .. " " end
  return s .. "}"
end

function Forged_Mailbox.debug( ... )
  if m.debug_enabled then
    local messages = ""
    for i = 1, getn( arg ) do
      local message = arg[ i ]
      if message then
        messages = messages == "" and "" or messages .. ", "
        if type( message ) == 'table' then
          messages = messages .. Forged_Mailbox.dump( message )
        else
          messages = messages .. message
        end
      end
    end

    m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473Forged_Mailbox|r: %s", messages ) )
  end
end

Forged_Mailbox:init()
