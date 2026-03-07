local m = Forged_Mailbox
local getn = table.getn ---@diagnostic disable-line: deprecated

---@param timestamp number
local function day_marker( timestamp )
  local t = date( "*t", timestamp )
  -- Keep consistent with the date picker: WoW's time({year,month,day}) defaults to midday.
  -- The Log filter expands this marker by +/- 12h to include the full day.
  return time( { year = t.year, month = t.month, day = t.day } )
end

function Forged_Mailbox.log.set_default_period()
  m.log = m.log or {}

  local end_time = day_marker( time() )
  -- Inclusive day marker window (expanded to full day in filter): use 29 days back
  -- to show the last 30 days including today.
  local start_time = day_marker( time() - (29 * 86400) )

  m.log.Received_start_time = start_time
  m.log.Received_end_time = end_time
  m.log.Sent_start_time = start_time
  m.log.Sent_end_time = end_time

  if m.api and m.api.Forged_MailboxLogStartTimeText then
    m.api.Forged_MailboxLogStartTimeText:SetText( date( L[ "date_format" ], start_time ) )
  end
  if m.api and m.api.Forged_MailboxLogEndTimeText then
    m.api.Forged_MailboxLogEndTimeText:SetText( date( L[ "date_format" ], end_time ) )
  end
end

function Forged_Mailbox.log.load()
  m.api.Forged_MailboxLogTitleText:SetText( "Log" )
  if m.api.MailFrameTab4 then
    m.api.MailFrameTab4:SetText( "Log" )
  end

  m.log = m.log or {}

  local font_file = "FONTS\\ARIALN.TTF"
  local font_size = 11

  for i = 1, 10 do
    m.api[ "Forged_MailboxLogItem" .. i .. "Background" ]:SetVertexColor( .5, .5, .5, 0.6 )
    m.api[ "Forged_MailboxLogItem" .. i .. "TimeStamp" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "Forged_MailboxLogItem" .. i .. "TimeStamp" ]:SetJustifyH( "LEFT" )
    m.api[ "Forged_MailboxLogItem" .. i .. "TimeStamp" ]:SetFont( font_file, font_size )
    m.api[ "Forged_MailboxLogItem" .. i .. "Participant" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "Forged_MailboxLogItem" .. i .. "Participant" ]:SetJustifyH( "RIGHT" )
    m.api[ "Forged_MailboxLogItem" .. i .. "Participant" ]:SetFont( font_file, font_size )
    m.api[ "Forged_MailboxLogItem" .. i .. "Subject" ]:SetJustifyH( "LEFT" )
    m.api[ "Forged_MailboxLogItem" .. i .. "Subject" ]:SetFont( font_file, font_size )
    m.api[ "Forged_MailboxLogItem" .. i .. "Money" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "Forged_MailboxLogItem" .. i .. "Money" ]:SetJustifyH( "LEFT" )
    m.api[ "Forged_MailboxLogItem" .. i .. "Money" ]:SetFont( font_file, font_size )
    m.api[ "Forged_MailboxLogItem" .. i .. "Status" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if i > 1 then
      m.api[ "Forged_MailboxLogItem" .. i ]:SetPoint( "TOPLEFT", m.api[ "Forged_MailboxLogItem" .. i - 1 ], "BOTTOMLEFT", 0, -1 )
    end
  end
  m.api.Forged_MailboxLogItem10Background:Hide()

  m.api.Forged_MailboxLogStatusText:SetTextColor( 1, 1, 1, 1 )
  m.api.Forged_MailboxLogStatusText:SetFont( "Fonts\\FRIZQT__.TTF", 10 )

  if m.skin_uipanel_scrollbar and m.api and m.api.Forged_MailboxLogScrollFrameScrollBar then
    m.skin_uipanel_scrollbar( m.api.Forged_MailboxLogScrollFrameScrollBar )
  end
  m.api.Forged_MailboxLogScrollFrameScrollBar:SetValueStep( 1 )
  m.api.Forged_MailboxLogScrollFrameScrollBar:SetScript( "OnValueChanged", m.log.on_scroll_value_changed )

  m.api.Forged_MailboxLogScrollFrame:SetScript( "OnMouseWheel", function()
    m.log.scroll( arg1 * 10 )
  end )
  m.api.Forged_MailboxLogScrollFrameScrollBarScrollUpButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( 10 )
  end )
  m.api.Forged_MailboxLogScrollFrameScrollBarScrollDownButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( -10 )
  end )

  m.api.Forged_MailboxLogFiltersButton:SetText( "Filters" )
  m.api.Forged_MailboxLogFiltersButton:GetFontString():SetPoint( "LEFT", m.api.Forged_MailboxLogFiltersButton, "LEFT", 10, 0 )

  m.api.Forged_MailboxLogFiltersButton:SetScript( "OnMouseDown", function()
    m.api.Forged_MailboxLogFiltersButtonArrow:SetPoint( "RIGHT", -8, -3 )
  end )
  m.api.Forged_MailboxLogFiltersButton:SetScript( "OnMouseUp", function()
    m.api.Forged_MailboxLogFiltersButtonArrow:SetPoint( "RIGHT", -8, -1 )
  end )

  m.api.Forged_MailboxLogStartTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.Forged_MailboxLogStartTimeButton:SetScale( 0.9 )
  m.api.Forged_MailboxLogEndTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.Forged_MailboxLogEndTimeButton:SetScale( 0.9 )

  -- Period fields should not be clickable; only the arrow buttons open the calendar.
  m.api.Forged_MailboxLogStartTime:SetScript( "OnClick", function() end )
  m.api.Forged_MailboxLogEndTime:SetScript( "OnClick", function() end )

  m.api.Forged_MailboxLogPlayersDropDown:SetScale( 0.9 )
  m.api.UIDropDownMenu_SetText( "All players", m.api.Forged_MailboxLogPlayersDropDown )

  m.log.dropdown_filters = m.api.CreateFrame( "Frame", "Forged_MailboxDropDownFiltersLog" )
  m.log.dropdown_filters.displayMode = "MENU"
  m.log.dropdown_filters.info = {}
end

function Forged_Mailbox.log.players_dropdown_on_load()
  m.api.UIDropDownMenu_Initialize( m.api.Forged_MailboxLogPlayersDropDown, function()
    local info = {}
    info.notCheckable = 1
    info.text = "All players"
    info.arg1 = info.text
    info.arg2 = "All"
    info.func = m.log.select_player
    m.api.UIDropDownMenu_AddButton( info )

    if not m.log.current_log_type then return end

    local players = {}
    for _, v in ipairs( m.api.ForgedMailboxLogDB[ m.log.current_log_type ] ) do
      if v then
        players[ v.participant ] = players[ v.participant ] and players[ v.participant ] + 1 or 1
      end
    end

    for player, count in pairs( players ) do
      info.text = player .. " (" .. count .. ")"
      info.arg1 = player
      info.arg2 = nil
      m.api.UIDropDownMenu_AddButton( info )
    end
  end )
end

function Forged_Mailbox.log.select_player( player, is_all )
  m.api.UIDropDownMenu_SetText( player, m.api.Forged_MailboxLogPlayersDropDown )
  if is_all then
    m.log.filter_player = nil
  else
    m.log.filter_player = player
  end
  m.log.populate( m.log.current_log_type )
end

function Forged_Mailbox.log.filter_dropdown()
  if m.log.dropdown_filters.initialize ~= Forged_Mailbox.log.filters_menu then
    m.api.CloseDropDownMenus()
    m.log.dropdown_filters.initialize = Forged_Mailbox.log.filters_menu
  end
  m.api.ToggleDropDownMenu( 1, nil, m.log.dropdown_filters, this:GetName(), 0, 0 )
end

function Forged_Mailbox.log.filters_menu( level )
  local filters = m.api.ForgedMailboxLogDB[ "Settings" ][ m.log.current_log_type .. "Filters" ] or {}
  local info = {}
  info.keepShownOnClick = 1

  local values = { "Money", "COD", "Other" }
  if m.log.current_log_type == "Received" then
    table.insert( values, "Returned" )
    table.insert( values, "AH" )
  end

  if level == 1 then
    for _, filter in values do
      info.text = L[ filter ]
      info.checked = filters[ filter ]
      info.arg1 = filter
      info.func = m.log.toggle_filter
      if filter == "AH" then info.hasArrow = 1 end

      m.api.UIDropDownMenu_AddButton( info, level )
    end
  elseif level == 2 then
    for _, filter in { "Sold", "Cancelled", "Expired", "Won", "Outbid" } do
      info.text = L[ filter ]
      info.checked = filters[ "AH" .. filter ]
      info.arg1 = filter
      info.arg2 = "AH"
      info.func = m.log.toggle_filter
      m.api.UIDropDownMenu_AddButton( info, level )
    end
  end
end

function Forged_Mailbox.log.toggle_filter( filter, parent_filter )
  if not parent_filter then parent_filter = "" end
  local filter_value = m.api.ForgedMailboxLogDB[ "Settings" ][ m.log.current_log_type .. "Filters" ][ parent_filter .. filter ]

  m.api.ForgedMailboxLogDB[ "Settings" ][ m.log.current_log_type .. "Filters" ][ parent_filter .. filter ] = not filter_value
  m.log.populate( m.log.current_log_type )
end

function Forged_Mailbox.log.show_calendar()
  if m.calendar.is_visible() then
    m.calendar.hide()
  else
    local text = string.gsub( this:GetName(), "Button", "Text" )

    local v = m.log.current_log_type .. (string.find( text, "Start" ) and "_start_time" or "_end_time")
    local current_date = m.log[ v ]
    if type( current_date ) ~= "number" then
      current_date = time()
    end

    m.calendar.show( m.api.ForgedMailboxLogDB[ m.log.current_log_type ], current_date, this, function( selected_date )
      local date_str = date( L[ "date_format" ], selected_date )
      m.api[ text ]:SetText( date_str )
      m.log[ v ] = selected_date
      m.log.populate( m.log.current_log_type )
    end, { allow_any_past_dates = true } )
  end
end

function Forged_Mailbox.log.scroll( step )
  local scroll_bar = m.api.Forged_MailboxLogScrollFrameScrollBar
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

function Forged_Mailbox.log.on_scroll_value_changed()
  local function round( num )
    return num + (2 ^ 52 + 2 ^ 51) - (2 ^ 52 + 2 ^ 51)
  end

  local scrollBar = m.api.Forged_MailboxLogScrollFrameScrollBar
  local scrollUp = m.api.Forged_MailboxLogScrollFrameScrollBarScrollUpButton
  local scrollDown = m.api.Forged_MailboxLogScrollFrameScrollBarScrollDownButton

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

  m.log.populate( m.log.current_log_type, currentVal )
end

---@alias LogType
---| "Sent"
---| "Received"

---@param log_type LogType
---@param state table
function Forged_Mailbox.log.add( log_type, state )
  -- Always collect log data; the /tm log toggle only controls tab visibility.
  if m.ensure_savedvars then
    m.ensure_savedvars()
  end
  m.debug( "Logging " .. log_type .. " message" )

  local data = {
    timestamp = time(),
    icon = state.icon,
    item = state.item
  }

  if state.cod and state.cod > 0 then data.cod = tonumber( state.cod ) end
  if log_type == "Sent" then
    data.participant = state.to
    data.subject = state.sent_subject
    if state.send_money and state.sent_money > 0 then data.money = tonumber( state.sent_money ) end
  else -- Received
    data.participant = state.from
    data.subject = state.subject
    data.returned = state.returned
    data.gm = state.gm

    if type( state.days_left ) == "number" or tonumber( state.days_left ) then
      data.days_left = tonumber( state.days_left )
    end

    if state.money and state.money > 0 then data.money = tonumber( state.money ) end

    if string.find( data.subject, string.gsub( m.api.AUCTION_SOLD_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Sold"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Removed"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Expired"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_WON_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Won"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Outbid"
    end
  end

  if m.api and m.api.ForgedMailboxLogDB and m.api.ForgedMailboxLogDB[ log_type ] then
    table.insert( m.api.ForgedMailboxLogDB[ log_type ], data )
  end
end

---@param log_type LogType
---@param index number?
function Forged_Mailbox.log.populate( log_type, index )
  m.log.current_log_type = log_type
  if not m.log[ log_type .. "_start_time" ] or not m.log[ log_type .. "_end_time" ] then
    m.log.set_default_period()
  end
  local filters = m.api.ForgedMailboxLogDB[ "Settings" ][ log_type .. "Filters" ] or {}
  local display_start_time = m.log[ log_type .. "_start_time" ]
  local display_end_time = m.log[ log_type .. "_end_time" ]
  local start_time = display_start_time
  local end_time = display_end_time
  if start_time then start_time = start_time - 43200 end
  if end_time then end_time = end_time + 43140 end

  local log = m.filter( m.api.ForgedMailboxLogDB[ log_type ], function( item )
    local ret =
        (filters.Money and item.money and item.money > 0 and (not item.cod or item.cod == 0) and not item.ah)
        or
        (filters.COD and item.cod and item.cod > 0)
        or
        (filters.Other and (not item.cod or item.cod == 0) and not item.ah and not item.returned and (not item.money or item.money == 0))
        or
        (filters.Returned and item.returned)
        or
        (filters.AH and filters.AHWon and item.ah == "Won")
        or
        (filters.AH and filters.AHSold and item.ah == "Sold")
        or
        (filters.AH and filters.AHCancelled and item.ah == "Removed")
        or
        (filters.AH and filters.AHOutbid and item.ah == "Outbid")
        or
        (filters.AH and filters.AHExpired and item.ah == "Expired")

    if m.log.filter_player then
      ret = ret and item.participant == m.log.filter_player
    end
    if start_time then
      ret = ret and item.timestamp >= start_time
    end
    if end_time then
      ret = ret and item.timestamp <= end_time
    end

    return ret
  end )

  -- Display newest entries first.
  table.sort( log, function( a, b )
    return (tonumber( a.timestamp ) or 0) > (tonumber( b.timestamp ) or 0)
  end )

  m.api.Forged_MailboxLogStartTimeText:SetText( display_start_time and date( L[ "date_format" ], display_start_time ) or "" )
  m.api.Forged_MailboxLogEndTimeText:SetText( display_end_time and date( L[ "date_format" ], display_end_time ) or "" )

  if not log then return end
  local log_count = getn( log )

  m.api.Forged_MailboxLogScrollFrameScrollBar:SetMinMaxValues( 0, math.max( 0, log_count - 10 ) )

  if not index then
    m.api.Forged_MailboxLogScrollFrameScrollBar:SetValue( 0 )
    m.api.Forged_MailboxLogScrollFrameScrollBar:SetScript( "OnUpdate", function()
      m.api.Forged_MailboxLogScrollFrameScrollBar:SetValue( 0 )
      m.api.Forged_MailboxLogScrollFrameScrollBar:SetScript( "OnUpdate", nil )
    end )

    index = 0
  end

  m.api.Forged_MailboxLogTitleText:SetText( string.format( "%s [%s]", L[ "Log" ], L[ log_type ] ) )
  m.api.Forged_MailboxLogStatusText:SetText( string.format( "Showing %d-%d of %d", (index == 0 and log_count == 0) and index or index + 1,
  math.min( log_count, index + 10 ), log_count ) )

  for i = 1, 10 do
    if log[ index + i ] then
      local entry = log[ index + i ]

      m.api[ "Forged_MailboxLogItem" .. i .. "IconTexture" ]:SetTexture( entry.icon or "Interface/Icons/INV_Misc_Note_01" )
      m.api[ "Forged_MailboxLogItem" .. i .. "Icon" ].item = entry.item
      m.api[ "Forged_MailboxLogItem" .. i .. "TimeStamp" ]:SetText( date( L[ "date_format" ] .. " " .. L[ "time_format" ], entry.timestamp ) )
      m.api[ "Forged_MailboxLogItem" .. i .. "Subject" ]:SetText( entry.subject )

      local status_texture = m.api[ "Forged_MailboxLogItem" .. i .. "Status" ]
      status_texture:ClearAllPoints()
      status_texture:SetPoint( "TOPRIGHT", 4, -10 )
      status_texture:SetTexture( "" )
      if entry.ah then
        m.api[ "Forged_MailboxLogItem" .. i .. "Participant" ]:SetText( entry.ah or "AH" )
      else
        m.api[ "Forged_MailboxLogItem" .. i .. "Participant" ]:SetText( entry.participant )
      end
      if entry.returned then
        status_texture:SetTexture( "Interface\\Addons\\Forged_Mailbox\\assets\\RetArrow.blp" )
        local w = m.api[ "Forged_MailboxLogItem" .. i .. "Participant" ]:GetStringWidth()
        status_texture:SetPoint( "TOPRIGHT", -w + 4, -9 )
      end

      if entry.money and entry.money > 0 then
        local cod = (entry.cod and entry.cod > 0) and "COD: " or " "
        m.api[ "Forged_MailboxLogItem" .. i .. "Money" ]:SetText( cod .. m.format_money( entry.money ) )
      elseif entry.cod then
        m.api[ "Forged_MailboxLogItem" .. i .. "Money" ]:SetText( "COD" .. (entry.cod > 1 and (": " .. m.format_money( entry.cod )) or "") )
      else
        m.api[ "Forged_MailboxLogItem" .. i .. "Money" ]:SetText( "" )
      end

      m.api[ "Forged_MailboxLogItem" .. i ]:Show();
    else
      m.api[ "Forged_MailboxLogItem" .. i ]:Hide();
    end
  end
end
