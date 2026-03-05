local m = Forged_Mailbox
local getn = table.getn ---@diagnostic disable-line: deprecated

m.ledger = m.ledger or {}

local LEDGER_ROW_ICON = "Interface/Icons/INV_Misc_Note_06"
local LEDGER_SUBROW_INDENT = "  "

local function escape_lua_pattern( s )
  if type( s ) ~= "string" then return "" end
  return (string.gsub( s, "([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1" ))
end

local function strip_auction_subject_prefix( subject )
  if type( subject ) ~= "string" then return "" end
  if not m.api then return subject end

  -- Remove the localized auction prefix (e.g. "Auction successful: ") and keep only the item/remaining text.
  for _, key in ipairs( {
    "AUCTION_SOLD_MAIL_SUBJECT",
    "AUCTION_REMOVED_MAIL_SUBJECT",
    "AUCTION_EXPIRED_MAIL_SUBJECT",
    "AUCTION_WON_MAIL_SUBJECT",
    "AUCTION_OUTBID_MAIL_SUBJECT",
  } ) do
    local pattern = m.api[ key ]
    if type( pattern ) == "string" and pattern ~= "" then
      local stem = string.gsub( pattern, "%%s", "" )
      local escaped_stem = escape_lua_pattern( stem )
      if escaped_stem ~= "" then
        subject = string.gsub( subject, "^" .. escaped_stem, "" )
      end
    end
  end

  subject = string.gsub( subject, "^%s+", "" )
  return subject
end

local function should_hide_subrow_participant( row, participant )
  if row and row.ah then
    return true
  end

  if not participant or participant == "" then
    return false
  end

  local p = string.lower( participant )
  return string.find( p, "auction house", 1, true ) ~= nil
      or string.find( p, "acution house", 1, true ) ~= nil
end

---@param timestamp number
local function format_ledger_day_label( timestamp )
  if type( timestamp ) ~= "number" then return "" end
  local t = date( "*t", timestamp )
  if type( t ) ~= "table" or type( t.day ) ~= "number" then
    return date( L[ "date_format" ], timestamp )
  end
  return string.format( "%s %d %s", date( "%A", timestamp ), t.day, date( "%B %Y", timestamp ) )
end

---@param copper number
function Forged_Mailbox.ledger.format_money_icons( copper )
  if type( copper ) ~= "number" then return "-" end

  local is_negative = copper < 0
  local value = math.abs( copper )

  local gold = math.floor( value / 10000 )
  local silver = math.floor( (value - gold * 10000) / 100 )
  local copper_remain = value - (gold * 10000) - (silver * 100)

  local formatted = string.format( "%dg %ds %dc", gold, silver, copper_remain )
  if is_negative then
    return "-" .. formatted
  end
  return formatted
end

---@param timestamp number
local function day_start( timestamp )
  local t = date( "*t", timestamp )
  return time( { year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 } )
end

function Forged_Mailbox.ledger.set_default_period()
  m.ledger = m.ledger or {}
  m.ledger.daily_end_time = day_start( time() )
  -- Inclusive day buckets: use 29 days back to show the last 30 days including today.
  m.ledger.daily_start_time = day_start( time() - (29 * 86400) )

  if m.api and m.api.Forged_MailboxLedgerStartTimeText then
    m.api.Forged_MailboxLedgerStartTimeText:SetText( date( L[ "date_format" ], m.ledger.daily_start_time ) )
  end
  if m.api and m.api.Forged_MailboxLedgerEndTimeText then
    m.api.Forged_MailboxLedgerEndTimeText:SetText( date( L[ "date_format" ], m.ledger.daily_end_time ) )
  end
end

---@param days_left number?
---@param reference_time number?
local function infer_received_timestamp_from_days_left( days_left, reference_time )
  if type( days_left ) ~= "number" then return nil end
  if type( reference_time ) ~= "number" then
    reference_time = time()
  end

  -- Vanilla mail expiry is typically 30 days; the API only exposes "days left",
  -- so we infer received date from that.
  local max_days = 30
  local age_days = max_days - days_left
  if age_days < 0 then age_days = 0 end
  if age_days > max_days then age_days = max_days end

  return reference_time - (age_days * 86400)
end

local function safe_pairs( t )
  if type( t ) == "table" then
    return pairs( t )
  end
  return pairs( {} )
end

local function get_visible_row_frame( i )
  return m.api and m.api[ "Forged_MailboxLedgerItem" .. i ]
end

local function get_visible_subrow_frame( i )
  return m.api and m.api[ "Forged_MailboxLedgerSubItem" .. i ]
end

function Forged_Mailbox.ledger.on_row_click( i )
  local frame = get_visible_row_frame( i )
  if not frame then return end

  local row = frame.fmb_row_data
  if type( row ) ~= "table" then return end
  if row.kind ~= "day" then return end

  if m.ledger.expanded_day and m.ledger.expanded_day == row.day then
    m.ledger.expanded_day = nil
  else
    m.ledger.expanded_day = row.day
  end

  local scroll_bar = m.api and m.api.Forged_MailboxLedgerScrollFrameScrollBar
  local index = scroll_bar and scroll_bar:GetValue() or 0
  if type( index ) == "number" then
    index = math.floor( index + 0.5 )
  else
    index = 0
  end
  m.ledger.populate( nil, index )
end

function Forged_Mailbox.ledger.load()
  m.ledger = m.ledger or {}
  m.ledger.current_log_type = "Daily"

  if m.api.MailFrameTab3 then
    m.api.MailFrameTab3:SetText( "Ledger" )
    m.api.MailFrameTab3:Show()
  end

  if m.api.MailFrameTab2 and m.api.MailFrameTab3 then
    m.api.MailFrameTab3:ClearAllPoints()
    m.api.MailFrameTab3:SetPoint( "LEFT", m.api.MailFrameTab2, "RIGHT", -8, 0 )
  end

  if m.api.Forged_MailboxLedgerTitleText then
    m.api.Forged_MailboxLedgerTitleText:SetText( "Ledger" )
  end

  local font_file = "FONTS\\ARIALN.TTF"
  local font_size = 11

  local entries_parent = m.api and m.api.Forged_MailboxLedgerEntriesFrame
  if entries_parent and m.api and m.api.CreateFrame then
    for i = 1, 10 do
      local sub_name = "Forged_MailboxLedgerSubItem" .. i
      if not m.api[ sub_name ] then
        local sub = m.api.CreateFrame( "Frame", sub_name, entries_parent )
        sub:SetHeight( 30 )
        sub:SetPoint( "TOPLEFT", entries_parent, "TOPLEFT", -5, 0 )
        sub:SetPoint( "RIGHT", entries_parent, "RIGHT", 0, 0 )
        if i > 1 and m.api[ "Forged_MailboxLedgerSubItem" .. (i - 1) ] then
          sub:ClearAllPoints()
          sub:SetPoint( "TOPLEFT", m.api[ "Forged_MailboxLedgerSubItem" .. (i - 1) ], "BOTTOMLEFT", 0, -1 )
          sub:SetPoint( "RIGHT", entries_parent, "RIGHT", 0, 0 )
        end

        local bg = sub:CreateTexture( sub_name .. "Background", "ARTWORK" )
        bg:SetTexture( "Interface/Buttons/WHITE8x8" )
        bg:SetHeight( 1 )
        bg:SetPoint( "BOTTOMLEFT", sub, "BOTTOMLEFT", 0, -1 )
        bg:SetPoint( "RIGHT", sub, "RIGHT", 0, 0 )

        local money = sub:CreateFontString( sub_name .. "Money", "ARTWORK", "GameFontNormal" )
        money:SetWidth( 80 )
        money:SetHeight( 14 )
        money:SetPoint( "RIGHT", sub, "RIGHT", -4, 0 )

        local idx = sub:CreateFontString( sub_name .. "Index", "ARTWORK", "GameFontNormal" )
        idx:SetWidth( 20 )
        idx:SetHeight( 14 )
        idx:SetPoint( "LEFT", sub, "LEFT", 10, 0 )
        idx:SetJustifyH( "RIGHT" )

        local subject = sub:CreateFontString( sub_name .. "Subject", "ARTWORK", "GameFontNormal" )
        subject:SetHeight( 14 )
        subject:SetPoint( "LEFT", idx, "RIGHT", 8, 0 )
        subject:SetPoint( "RIGHT", money, "LEFT", -8, 0 )

        sub:Hide()
      end
    end
  end

  for i = 1, 10 do
    m.api[ "Forged_MailboxLedgerItem" .. i .. "Background" ]:SetVertexColor( .5, .5, .5, 0.6 )
    m.api[ "Forged_MailboxLedgerItem" .. i .. "TimeStamp" ]:SetTextColor( 1, 0.82, 0, 1 )
    m.api[ "Forged_MailboxLedgerItem" .. i .. "TimeStamp" ]:SetJustifyH( "LEFT" )
    m.api[ "Forged_MailboxLedgerItem" .. i .. "TimeStamp" ]:SetFont( font_file, font_size )
    if m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ] then
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:SetTextColor( 1, 1, 1, 1 )
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:SetJustifyH( "LEFT" )
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:SetFont( font_file, font_size )
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:Show()
    end
    m.api[ "Forged_MailboxLedgerItem" .. i .. "Participant" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "Forged_MailboxLedgerItem" .. i .. "Participant" ]:SetJustifyH( "RIGHT" )
    m.api[ "Forged_MailboxLedgerItem" .. i .. "Participant" ]:SetFont( font_file, font_size )
    if m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ] then
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ]:SetText( "" )
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ]:Hide()
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ]:SetTextColor( 1, 1, 1, 1 )
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ]:SetJustifyH( "LEFT" )
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ]:SetFont( font_file, font_size )
    end
    if m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ] then
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:SetText( "" )
    end
    if m.api[ "Forged_MailboxLedgerItem" .. i .. "Icon" ] then
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Icon" ]:Show()
    end
    if m.api[ "Forged_MailboxLedgerItem" .. i .. "IconTexture" ] then
      m.api[ "Forged_MailboxLedgerItem" .. i .. "IconTexture" ]:SetTexture( LEDGER_ROW_ICON )
    end
    if m.api[ "Forged_MailboxLedgerItem" .. i .. "Status" ] then
      m.api[ "Forged_MailboxLedgerItem" .. i .. "Status" ]:SetTexture( "" )
    end
    m.api[ "Forged_MailboxLedgerItem" .. i .. "Status" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if i > 1 then
      m.api[ "Forged_MailboxLedgerItem" .. i ]:SetPoint( "TOPLEFT", m.api[ "Forged_MailboxLedgerItem" .. i - 1 ], "BOTTOMLEFT", 0, -1 )
    end

    local sub = get_visible_subrow_frame( i )
    if sub then
      sub:EnableMouse( false )
      if i > 1 then
        sub:ClearAllPoints()
        sub:SetPoint( "TOPLEFT", get_visible_subrow_frame( i - 1 ), "BOTTOMLEFT", 0, -1 )
        if entries_parent then
          sub:SetPoint( "RIGHT", entries_parent, "RIGHT", 0, 0 )
        end
      end

      local sub_bg = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Background" ]
      if sub_bg then
        sub_bg:SetVertexColor( .5, .5, .5, 0.25 )
      end

      local sub_subject = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Subject" ]
      if sub_subject then
        sub_subject:SetTextColor( 1, 1, 1, 1 )
        sub_subject:SetJustifyH( "LEFT" )
        sub_subject:SetFont( font_file, font_size )
      end

      local sub_index = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Index" ]
      if sub_index then
        sub_index:SetTextColor( 1, 1, 1, 1 )
        sub_index:SetJustifyH( "RIGHT" )
        sub_index:SetFont( font_file, font_size )
      end

      local sub_money = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Money" ]
      if sub_money then
        sub_money:SetTextColor( 1, 1, 1, 1 )
        sub_money:SetJustifyH( "RIGHT" )
        sub_money:SetFont( font_file, font_size )
      end

      sub:Hide()
    end

    if m.api[ "Forged_MailboxLedgerItem" .. i ] then
      local row_index = i
      m.api[ "Forged_MailboxLedgerItem" .. i ]:EnableMouse( true )
      m.api[ "Forged_MailboxLedgerItem" .. i ]:SetScript( "OnMouseUp", function()
        m.ledger.on_row_click( row_index )
      end )
    end
  end
  m.api.Forged_MailboxLedgerItem10Background:Hide()

  m.api.Forged_MailboxLedgerStatusText:SetTextColor( 1, 1, 1, 1 )
  m.api.Forged_MailboxLedgerStatusText:SetFont( "Fonts\\FRIZQT__.TTF", 10 )
  m.api.Forged_MailboxLedgerScrollFrameScrollBar:SetValueStep( 1 )
  m.api.Forged_MailboxLedgerScrollFrameScrollBar:SetScript( "OnValueChanged", m.ledger.on_scroll_value_changed )

  m.api.Forged_MailboxLedgerScrollFrame:SetScript( "OnMouseWheel", function()
    m.ledger.scroll( arg1 * 10 )
  end )
  m.api.Forged_MailboxLedgerScrollFrameScrollBarScrollUpButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.ledger.scroll( 10 )
  end )
  m.api.Forged_MailboxLedgerScrollFrameScrollBarScrollDownButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.ledger.scroll( -10 )
  end )

  m.api.Forged_MailboxLedgerFiltersButton:SetText( "Filters" )
  m.api.Forged_MailboxLedgerFiltersButton:GetFontString():SetPoint( "LEFT", m.api.Forged_MailboxLedgerFiltersButton, "LEFT", 10, 0 )

  -- Ledger is a daily money summary:
  -- - remove Filters dropdown
  -- - keep Period (start/end) filter
  if m.api.Forged_MailboxLedgerFiltersButton then m.api.Forged_MailboxLedgerFiltersButton:Hide() end
  if m.api.Forged_MailboxLedgerStartTime then m.api.Forged_MailboxLedgerStartTime:Show() end
  if m.api.Forged_MailboxLedgerEndTime then m.api.Forged_MailboxLedgerEndTime:Show() end
  if m.api.Forged_MailboxLedgerPlayersDropDown then m.api.Forged_MailboxLedgerPlayersDropDown:Hide() end
  if m.api.Forged_MailboxLedgerSentButton then m.api.Forged_MailboxLedgerSentButton:Hide() end
  if m.api.Forged_MailboxLedgerReceivedButton then m.api.Forged_MailboxLedgerReceivedButton:Hide() end

  m.api.Forged_MailboxLedgerStartTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.Forged_MailboxLedgerStartTimeButton:SetScale( 0.9 )
  m.api.Forged_MailboxLedgerEndTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.Forged_MailboxLedgerEndTimeButton:SetScale( 0.9 )

  m.api.Forged_MailboxLedgerStartTime:SetScript( "OnClick", function() end )
  m.api.Forged_MailboxLedgerEndTime:SetScript( "OnClick", function() end )

  -- Player dropdown is unused for daily totals.
end

function Forged_Mailbox.ledger.players_dropdown_on_load()
  -- Ledger is a daily aggregate view; player filtering is not used.
  if not m.api or not m.api.Forged_MailboxLedgerPlayersDropDown then return end
  m.api.UIDropDownMenu_Initialize( m.api.Forged_MailboxLedgerPlayersDropDown, function()
    local info = {}
    info.notCheckable = 1
    info.text = "All players"
    info.func = function() end
    m.api.UIDropDownMenu_AddButton( info )
  end )
end

function Forged_Mailbox.ledger.select_player( player, is_all )
  m.api.UIDropDownMenu_SetText( player, m.api.Forged_MailboxLedgerPlayersDropDown )
  if is_all then
    m.ledger.filter_player = nil
  else
    m.ledger.filter_player = player
  end
  m.ledger.populate( m.ledger.current_log_type )
end

function Forged_Mailbox.ledger.filter_dropdown()
  -- Filters dropdown removed for Ledger.
end

function Forged_Mailbox.ledger.filters_menu( level )
  local filters = m.api.ForgedMailboxLedgerDB[ "Settings" ][ m.ledger.current_log_type .. "Filters" ] or {}
  local info = {}
  info.keepShownOnClick = 1

  local values = { "Money", "COD", "Other" }
  if m.ledger.current_log_type == "Received" then
    table.insert( values, "Returned" )
    table.insert( values, "AH" )
  end

  if level == 1 then
    for _, filter in values do
      info.text = L[ filter ]
      info.checked = filters[ filter ]
      info.arg1 = filter
      info.func = m.ledger.toggle_filter
      if filter == "AH" then info.hasArrow = 1 end

      m.api.UIDropDownMenu_AddButton( info, level )
    end
  elseif level == 2 then
    for _, filter in { "Sold", "Cancelled", "Expired", "Won", "Outbid" } do
      info.text = L[ filter ]
      info.checked = filters[ "AH" .. filter ]
      info.arg1 = filter
      info.arg2 = "AH"
      info.func = m.ledger.toggle_filter
      m.api.UIDropDownMenu_AddButton( info, level )
    end
  end
end

function Forged_Mailbox.ledger.toggle_filter( filter, parent_filter )
  if not parent_filter then parent_filter = "" end
  local filter_value = m.api.ForgedMailboxLedgerDB[ "Settings" ][ m.ledger.current_log_type .. "Filters" ][ parent_filter .. filter ]

  m.api.ForgedMailboxLedgerDB[ "Settings" ][ m.ledger.current_log_type .. "Filters" ][ parent_filter .. filter ] = not filter_value
  m.ledger.populate( m.ledger.current_log_type )
end

function Forged_Mailbox.ledger.show_calendar( which )
  if m.calendar.is_visible() then
    m.calendar.hide()
  else
    if which ~= "Start" and which ~= "End" then
      which = "Start"
    end

    m.api.ForgedMailboxLedgerDB = m.api.ForgedMailboxLedgerDB or {}
    m.api.ForgedMailboxLedgerDB.Daily = m.api.ForgedMailboxLedgerDB.Daily or {}

    local date_data = {}
    local latest = nil
    for day in pairs( m.api.ForgedMailboxLedgerDB.Daily ) do
      if type( day ) == "number" then
        table.insert( date_data, { timestamp = day } )
        if (not latest) or day > latest then
          latest = day
        end
      end
    end

    if not latest then
      latest = time()
      table.insert( date_data, { timestamp = latest } )
    end

    local current_date
    if which == "Start" then
      current_date = m.ledger.daily_start_time
    else
      current_date = m.ledger.daily_end_time
    end
    if type( current_date ) ~= "number" then
      current_date = latest
    end

    m.calendar.show( date_data, current_date, this, function( selected_date )
      local day = day_start( selected_date )
      local date_str = date( L[ "date_format" ], selected_date )

      if which == "Start" then
        m.ledger.daily_start_time = day
        m.api.Forged_MailboxLedgerStartTimeText:SetText( date_str )
      else
        m.ledger.daily_end_time = day
        m.api.Forged_MailboxLedgerEndTimeText:SetText( date_str )
      end

      m.ledger.populate()
    end, { allow_any_past_dates = true } )
  end
end

function Forged_Mailbox.ledger.scroll( step )
  local scroll_bar = m.api.Forged_MailboxLedgerScrollFrameScrollBar
  local current = scroll_bar:GetValue()
  local min, max = scroll_bar:GetMinMaxValues()
  local new = current - step

  if new >= max then
    scroll_bar:SetValue( max )
  elseif new <= min then
    scroll_bar:SetValue( 0 )
  else
    scroll_bar:SetValue( new )
  end
end

function Forged_Mailbox.ledger.on_scroll_value_changed()
  local function round( num )
    return num + (2 ^ 52 + 2 ^ 51) - (2 ^ 52 + 2 ^ 51)
  end

  local scrollBar = m.api.Forged_MailboxLedgerScrollFrameScrollBar
  local scrollUp = m.api.Forged_MailboxLedgerScrollFrameScrollBarScrollUpButton
  local scrollDown = m.api.Forged_MailboxLedgerScrollFrameScrollBarScrollDownButton

  local minVal, maxVal = scrollBar:GetMinMaxValues()
  local currentVal = round( scrollBar:GetValue() )

  if currentVal <= round( minVal ) then
    scrollUp:Disable()
  else
    scrollUp:Enable()
  end

  if currentVal >= round( maxVal ) then
    scrollDown:Disable()
  else
    scrollDown:Enable()
  end

  m.ledger.populate( m.ledger.current_log_type, currentVal )
end

---@alias LogType
---| "Sent"
---| "Received"

---@param log_type LogType
---@param state table
function Forged_Mailbox.ledger.add( log_type, state )
  if log_type ~= "Received" then return end

  local money = tonumber( state and state.money ) or 0
  if money <= 0 then return end

  m.api.ForgedMailboxLedgerDB = m.api.ForgedMailboxLedgerDB or {}
  m.api.ForgedMailboxLedgerDB.Daily = m.api.ForgedMailboxLedgerDB.Daily or {}

  local received_ts = infer_received_timestamp_from_days_left( state and state.days_left, time() ) or time()
  local key = day_start( received_ts )

  local bucket = m.api.ForgedMailboxLedgerDB.Daily[ key ]
  if type( bucket ) == "number" then
    bucket = { Money = bucket }
  elseif type( bucket ) ~= "table" then
    bucket = {}
  end

  local subject = (state and state.subject) or ""
  local bucket_key = "Money"
  local is_ah_sold = false

  if subject ~= "" then
    if string.find( subject, string.gsub( m.api.AUCTION_SOLD_MAIL_SUBJECT, "%%s", "" ) ) then
      bucket_key = "AHSold"
      is_ah_sold = true
    elseif string.find( subject, string.gsub( m.api.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", "" ) ) then
      bucket_key = "AHCancelled"
    elseif string.find( subject, string.gsub( m.api.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "" ) ) then
      bucket_key = "AHExpired"
    elseif string.find( subject, string.gsub( m.api.AUCTION_WON_MAIL_SUBJECT, "%%s", "" ) ) then
      bucket_key = "AHWon"
    elseif string.find( subject, string.gsub( m.api.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "" ) ) then
      bucket_key = "AHOutbid"
    end
  end

  bucket[ bucket_key ] = (tonumber( bucket[ bucket_key ] ) or 0) + money
  if is_ah_sold then
    bucket.AHSoldCount = (tonumber( bucket.AHSoldCount ) or 0) + 1
  end
  m.api.ForgedMailboxLedgerDB.Daily[ key ] = bucket

  if m.api.Forged_MailboxLedgerFrame and m.api.Forged_MailboxLedgerFrame:IsShown() then
    m.ledger.populate()
  end
end

---@param log_type LogType
---@param index number?
function Forged_Mailbox.ledger.populate( log_type, index )
  m.ledger.current_log_type = "Daily"
  if not m.ledger.daily_start_time or not m.ledger.daily_end_time then
    m.ledger.set_default_period()
  end

  m.api.ForgedMailboxLedgerDB = m.api.ForgedMailboxLedgerDB or {}
  m.api.ForgedMailboxLedgerDB.Daily = m.api.ForgedMailboxLedgerDB.Daily or {}

  local start_day = m.ledger.daily_start_time
  local end_day = m.ledger.daily_end_time
  if start_day and end_day and start_day > end_day then
    start_day, end_day = end_day, start_day
  end

  local days = {}
  for day, bucket in safe_pairs( m.api.ForgedMailboxLedgerDB.Daily ) do
    if type( day ) == "number" then
      if start_day and day < start_day then
        -- Skip
      elseif end_day and day > end_day then
        -- Skip
      else
      local money_total = 0
      local sold_count = 0
      if type( bucket ) == "number" then
        money_total = bucket
      elseif type( bucket ) == "table" then
        money_total = money_total + (tonumber( bucket.Money ) or 0)
        money_total = money_total + (tonumber( bucket.AHSold ) or 0)
        money_total = money_total + (tonumber( bucket.AHCancelled ) or 0)
        money_total = money_total + (tonumber( bucket.AHExpired ) or 0)
        money_total = money_total + (tonumber( bucket.AHWon ) or 0)
        money_total = money_total + (tonumber( bucket.AHOutbid ) or 0)

        sold_count = sold_count + (tonumber( bucket.AHSoldCount ) or 0)
      end

      if money_total and money_total > 0 then
        table.insert( days, { day = day, total = money_total, sold_count = sold_count } )
      end
      end
    end
  end

  m.api.Forged_MailboxLedgerStartTimeText:SetText( start_day and date( L[ "date_format" ], start_day ) or "" )
  m.api.Forged_MailboxLedgerEndTimeText:SetText( end_day and date( L[ "date_format" ], end_day ) or "" )

  table.sort( days, function( a, b ) return a.day > b.day end )

  local expanded_day = m.ledger.expanded_day
  local expanded_log_entries = nil
  if expanded_day and m.api and m.api.ForgedMailboxLogDB and type( m.api.ForgedMailboxLogDB.Received ) == "table" then
    expanded_log_entries = {}
    for _, entry in ipairs( m.api.ForgedMailboxLogDB.Received ) do
      if type( entry ) == "table" and entry.ah then
        local received_ts = infer_received_timestamp_from_days_left(
          tonumber( entry.days_left ),
          tonumber( entry.timestamp ) or time()
        )
        local entry_day = day_start( received_ts or (tonumber( entry.timestamp ) or time()) )
        if entry_day == expanded_day then
          table.insert( expanded_log_entries, entry )
        end
      end
    end
    table.sort( expanded_log_entries, function( a, b )
      return (tonumber( a.timestamp ) or 0) > (tonumber( b.timestamp ) or 0)
    end )
  end

  local display_rows = {}
  for _, day_row in ipairs( days ) do
    table.insert( display_rows, { kind = "day", day = day_row.day, total = day_row.total, sold_count = day_row.sold_count } )
    if expanded_day and day_row.day == expanded_day and expanded_log_entries and getn( expanded_log_entries ) > 0 then
      for entry_index, entry in ipairs( expanded_log_entries ) do
        table.insert( display_rows, {
          kind = "mail",
          day = day_row.day,
          sub_index = entry_index,
          timestamp = tonumber( entry.timestamp ) or 0,
          participant = entry.participant,
          subject = entry.subject,
          money = tonumber( entry.money ) or 0,
          ah = entry.ah,
        } )
      end
    end
  end

  -- If the expanded day falls outside of the current period, collapse it.
  if expanded_day then
    local still_visible = false
    for _, row in ipairs( display_rows ) do
      if row.kind == "day" and row.day == expanded_day then
        still_visible = true
        break
      end
    end
    if not still_visible then
      m.ledger.expanded_day = nil
      expanded_day = nil
    end
  end

  local row_count = getn( display_rows )
  m.api.Forged_MailboxLedgerScrollFrameScrollBar:SetMinMaxValues( 0, math.max( 0, row_count - 10 ) )

  if not index then
    index = 0
    m.api.Forged_MailboxLedgerScrollFrameScrollBar:SetValue( index )
  end

  m.api.Forged_MailboxLedgerTitleText:SetText( L[ "Ledger" ] )
  m.api.Forged_MailboxLedgerStatusText:SetText(
    string.format(
      "Showing %d-%d of %d",
      (index == 0 and row_count == 0) and index or index + 1,
      math.min( row_count, index + 10 ),
      row_count
    )
  )

  for i = 1, 10 do
    local row = display_rows[ index + i ]
    local day_frame = get_visible_row_frame( i )
    local sub_frame = get_visible_subrow_frame( i )

    if not row then
      if day_frame then day_frame:Hide() end
      if sub_frame then sub_frame:Hide() end
    elseif row.kind == "day" then
      if sub_frame then sub_frame:Hide() end
      if day_frame then
        day_frame.fmb_row_data = row
        day_frame:Show()
      end

      if m.api[ "Forged_MailboxLedgerItem" .. i .. "Icon" ] then
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Icon" ]:Show()
      end
      if m.api[ "Forged_MailboxLedgerItem" .. i .. "IconTexture" ] then
        m.api[ "Forged_MailboxLedgerItem" .. i .. "IconTexture" ]:SetTexture( LEDGER_ROW_ICON )
      end
      if m.api[ "Forged_MailboxLedgerItem" .. i .. "TimeStamp" ] then
        m.api[ "Forged_MailboxLedgerItem" .. i .. "TimeStamp" ]:Show()
        m.api[ "Forged_MailboxLedgerItem" .. i .. "TimeStamp" ]:SetText( format_ledger_day_label( row.day ) )
      end
      if m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ] then
        if row.sold_count and row.sold_count > 0 then
          m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:SetText( string.format( "%d sale%s", row.sold_count, row.sold_count == 1 and "" or "s" ) )
        else
          m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:SetText( "" )
        end
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Money" ]:Show()
      end
      if m.api[ "Forged_MailboxLedgerItem" .. i .. "Participant" ] then
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Participant" ]:SetText( m.ledger.format_money_icons( row.total ) )
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Participant" ]:Show()
      end
      if m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ] then
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ]:SetText( "" )
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Subject" ]:Hide()
      end
      if m.api[ "Forged_MailboxLedgerItem" .. i .. "Status" ] then
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Status" ]:SetTexture( "" )
      end
      if m.api[ "Forged_MailboxLedgerItem" .. i .. "Background" ] then
        m.api[ "Forged_MailboxLedgerItem" .. i .. "Background" ]:SetVertexColor( .5, .5, .5, 0.6 )
      end
    else
      if day_frame then day_frame:Hide() end
      if sub_frame then
        sub_frame.fmb_row_data = row
        sub_frame:Show()
      end

      local ts = tonumber( row.timestamp ) or 0
      local subject = strip_auction_subject_prefix( row.subject or "" )
      local participant = row.participant or ""

      if should_hide_subrow_participant( row, participant ) then
        participant = ""
      end

      local money_text = m.ledger.format_money_icons( row.money )

      local details = subject
      if participant ~= "" then
        details = details .. " (" .. participant .. ")"
      end

      local sub_subject = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Subject" ]
      if sub_subject then
        sub_subject:SetText( LEDGER_SUBROW_INDENT .. details )
      end

      local sub_index = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Index" ]
      if sub_index then
        if row.sub_index then
          sub_index:SetText( tostring( row.sub_index ) )
        else
          sub_index:SetText( "" )
        end
      end

      local sub_money = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Money" ]
      if sub_money then
        if money_text and money_text ~= "-" and money_text ~= "0g 0s 0c" then
          sub_money:SetText( money_text )
        else
          sub_money:SetText( "n/a" )
        end
      end

      local sub_bg = m.api[ "Forged_MailboxLedgerSubItem" .. i .. "Background" ]
      if sub_bg then
        sub_bg:SetVertexColor( .5, .5, .5, 0.25 )
      end
    end
  end
end
