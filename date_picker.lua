Forged_Mailbox = Forged_Mailbox or {}
local m = Forged_Mailbox

if m.date_picker then return end
if m.Calendar then
  m.date_picker = m.Calendar
  return
end

---@class Calendar
---@field show fun( data: table, date: number, anchor: table, on_select: function )
---@field hide fun()
---@field is_visible fun():boolean

local M = {}

function M.new()
  local BTN_WIDTH = 25
  local BTN_HEIGHT = 20

  local calendar
  local set_year, set_month
  local year_dd, month_dd
  local date_data = {}
  local allow_any_past_dates = false
  local EARLIEST_YEAR = 2004
  local months = {}
  local days = {}
  local select_func

  for i = 1, 12 do
    local timestamp = time( { year = 2025, month = i, day = 1 } )
    months[ i ] = date( "%B", timestamp )
  end

  local function get_end_day_of_month( year, month )
    if month == 2 then
      if (mod( year, 4 ) == 0 and mod( year, 100 ) ~= 0) or mod( year, 400 ) == 0 then
        return 29
      else
        return 28
      end
    elseif month == 4 or month == 6 or month == 9 or month == 11 then
      return 30
    else
      return 31
    end
  end

  ---@alias DatePart
  ---| "Year"
  ---| "Month"
  ---| "Day"

  ---@param part DatePart
  local function get_valid_dates( part )
    local valid = {}

    if allow_any_past_dates then
      local now = time()
      local t = date( "*t", now )
      local current_year = tonumber( t.year )
      local current_month = tonumber( t.month )
      local current_day = tonumber( t.day )

      if part == "Year" then
        for y = EARLIEST_YEAR, current_year do
          valid[ y ] = true
        end
        return valid
      elseif part == "Month" then
        if not set_year then return valid end
        local max_month = (tonumber( set_year ) == current_year) and current_month or 12
        for mth = 1, max_month do
          valid[ mth ] = true
        end
        return valid
      elseif part == "Day" then
        if not set_year or not set_month then return valid end
        local end_day = get_end_day_of_month( tonumber( set_year ), tonumber( set_month ) )
        local max_day = end_day
        if tonumber( set_year ) == current_year and tonumber( set_month ) == current_month then
          max_day = current_day
        elseif tonumber( set_year ) > current_year or (tonumber( set_year ) == current_year and tonumber( set_month ) > current_month) then
          max_day = 0
        end
        for d = 1, max_day do
          valid[ d ] = true
        end
        return valid
      end
    end

    for i, v in ipairs( date_data ) do
      local year = tonumber( date( "%Y", v.timestamp ) )
      local month = tonumber( date( "%m", v.timestamp ) )
      local day = tonumber( date( "%d", v.timestamp ) )

      if year and month and day then
        if part == "Day" and year == set_year and month == set_month then
          valid[ day ] = valid[ day ] and valid[ day ] + 1 or 1
        elseif part == "Month" and year == set_year then
          valid[ month ] = true
        elseif part == "Year" then
          valid[ year ] = true
        end
      end
    end

    return valid
  end

  local function refresh()
    if allow_any_past_dates then
      local t = date( "*t", time() )
      local current_year = tonumber( t.year )
      local current_month = tonumber( t.month )

      if tonumber( set_year ) > current_year then
        set_year = current_year
      end
      if tonumber( set_year ) == current_year and tonumber( set_month ) > current_month then
        set_month = current_month
      end
    end

    local current_month = { year = set_year, month = set_month, day = "01" }
    local skip_days = date( "%w", time( current_month ) )
    local end_day = get_end_day_of_month( tonumber( set_year ), tonumber( set_month ) )

    for i = 1, 42 do
      days[ i ]:SetText( "" )
      days[ i ]:Disable()
      days[ i ]:Hide()
    end

    local valid_days = get_valid_dates( "Day" )
    for i = 1, end_day do
      local day = days[ i + skip_days ]
      local d = i
      day:SetText( i )

      if valid_days[ i ] then
        if type( valid_days[ i ] ) == "number" then
          day.mails = valid_days[ i ]
        else
          day.mails = nil
        end
        day:Enable()
      end
      day:Show()

      day:SetScript( "OnClick", function()
        local timestamp = time( { year = set_year, month = set_month, day = d } )
        if allow_any_past_dates and timestamp > time() then
          return
        end
        if select_func then
          select_func( timestamp )
        end
        calendar:Hide()
      end )
    end

    if tonumber( skip_days + end_day ) < 36 then
      calendar:SetHeight( 150 )
    else
      calendar:SetHeight( 170 )
    end

    m.api.UIDropDownMenu_SetText( months[ set_month ], month_dd )
    m.api.UIDropDownMenu_SetText( set_year, year_dd )
  end

  ---@param parent table
  ---@param index number
  local function create_date_button( parent, index )
    local button = m.api.CreateFrame( "Button", "Forged_MailboxCalendarDay" .. index .. "Button", parent, "UIPanelButtonTemplate" )
    button:SetWidth( BTN_WIDTH )
    button:SetHeight( BTN_HEIGHT )
    button:GetFontString():SetFont( "Fonts/FRIZQT__.TTF", 9 )
    button:GetFontString():SetTextColor( 1, 1, 1, 1 )

    local orig_disable = button.Disable
    button.Disable = function( self )
      orig_disable( self )
      button:GetFontString():SetTextColor( 0.5, 0.5, 0.5, 1 )
    end

    local orig_enable = button.Enable
    button.Enable = function( self )
      orig_enable( self )
      button:GetFontString():SetTextColor( 1, 1, 1, 1 )
    end

    button:SetScript( "OnEnter", function()
      if type( button.mails ) ~= "number" then
        return
      end
      m.api.GameTooltip:SetOwner( this, "ANCHOR_RIGHT" )
      m.api.GameTooltip:SetText( button.mails .. " mail" .. (button.mails > 1 and "s" or ""), 1, 1, 1, 1, true )
      m.api.GameTooltip:Show()
    end )

    button:SetScript( "OnLeave", function()
      m.api.GameTooltip:Hide()
    end )

    return button
  end

  ---@param parent table
  ---@param name DatePart
  ---@param on_select function
  ---@return table
  local function create_dropdown( parent, name, on_select )
    local dropdown = m.api.CreateFrame( "Frame", "Forged_MailboxDropdown" .. name, parent, "UIDropDownMenuTemplate" )

    m.api.UIDropDownMenu_Initialize( dropdown, function()
      local valid_dates = get_valid_dates( name )

      local keys = {}
      for i in pairs( valid_dates ) do
        table.insert( keys, i )
      end
      table.sort( keys, function( a, b )
        if name == "Year" then return a > b end
        return a < b
      end )

      for _, i in ipairs( keys ) do
        local info = {}
        info.arg1 = i
        info.arg2 = name == "Month" and months[ i ] or i
        info.value = info.arg1
        info.text = info.arg2

        -- Vanilla UIDropDownMenu calls without args; use `this`.
        info.func = function()
          local index = this.arg1
          local value = this.arg2
          m.api.UIDropDownMenu_SetText( value, dropdown )
          m.api.CloseDropDownMenus()
          on_select( index, value )
        end

        m.api.UIDropDownMenu_AddButton( info )
      end
    end )

    return dropdown
  end

  local function create_calendar()
    local frame = m.api.CreateFrame( "Frame", "Forged_MailboxCalendarFrame" )
    frame:SetFrameStrata( "FULLSCREEN_DIALOG" )
    frame:SetWidth( 195 )
    frame:SetHeight( 170 )
    frame:SetClampedToScreen( true )
    frame:SetBackdrop( {
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      tile = false,
      tileSize = 0,
      edgeSize = 0.5,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    } )

    frame:SetBackdropColor( 0, 0, 0, 0.9 )
    frame:SetBackdropBorderColor( .4, .4, .4, 0.9 )
    frame:EnableMouse( true )
    frame:Hide()
    m.api.tinsert( m.api.UISpecialFrames, frame:GetName() )

    frame:SetScript( "OnLeave", function()
      if m.api.MouseIsOver( frame ) then return end

      -- Don't auto-hide while interacting with dropdown menu lists.
      for i = 1, 2 do
        local list = m.api[ "DropDownList" .. i ]
        if list and list:IsShown() then
          return
        end
      end

      calendar:Hide()
    end )

    year_dd = create_dropdown( frame, "Year", function( _, v )
      set_year = v
      refresh()
    end )
    year_dd:SetPoint( "TOPLEFT", -12, -5 )
    m.api.UIDropDownMenu_SetWidth( 55, year_dd )

    month_dd = create_dropdown( frame, "Month", function( v )
      set_month = v
      refresh()
    end )
    month_dd:SetPoint( "TOPLEFT", 70, -5 )
    m.api.UIDropDownMenu_SetWidth( 85, month_dd )

    for i = 1, 42 do
      table.insert( days, create_date_button( frame, i ) )
    end

    for i = 1, 6 do
      for j = 1, 7 do
        days[ (i - 1) * 7 + j ]:SetPoint( "TOPLEFT", frame, 10 + (j - 1) * BTN_WIDTH, -40 - (i - 1) * BTN_HEIGHT )
        days[ (i - 1) * 7 + j ]:Disable()
      end
    end

    return frame
  end

  local function show( data, current_date, anchor, on_select )
    date_data = data
    if type( on_select ) ~= "function" then on_select = nil end
    set_year = tonumber( date( "%Y", current_date ) )
    set_month = tonumber( date( "%m", current_date ) )
    select_func = on_select

    if not calendar then
      calendar = create_calendar()
    end

    calendar:SetPoint( "TOPRIGHT", anchor, "BOTTOMRIGHT", 100, 1 )

    refresh()
    calendar:Show()
  end

  ---@param data table
  ---@param current_date number
  ---@param anchor table
  ---@param on_select function
  ---@param opts table?
  local function show_with_opts( data, current_date, anchor, on_select, opts )
    allow_any_past_dates = opts and opts.allow_any_past_dates or opts and opts.allow_any or false
    show( data, current_date, anchor, on_select )
  end

  local function hide()
    if calendar then
      calendar:Hide()
    end
  end

  local function is_visible()
    if calendar then
      return calendar:IsVisible()
    end
    return false
  end

  ---@type Calendar
  return {
    show = show_with_opts,
    hide = hide,
    is_visible = is_visible
  }
end

m.date_picker = M
m.Calendar = M
return M
