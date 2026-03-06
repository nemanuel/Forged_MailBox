local m = Forged_Mailbox
local getn = table.getn ---@diagnostic disable-line: deprecated

local ATTACHMENTS_MAX = 21
local ATTACHMENTS_PER_ROW_SEND = 7
local ATTACHMENTS_MAX_ROWS_SEND = 3

local function get_send_button()
  return (m.api and (m.api.SendMailMailButton or m.api.MailMailButton)) or nil
end

local function item_bag_slot( item )
  if type( item ) ~= "table" then return end
  return item[ 1 ], item[ 2 ]
end

local function item_link( item )
  if type( item ) ~= "table" then return end
  return item[ 3 ]
end

local function ensure_item_link( item )
  if type( item ) ~= "table" then return item end
  if item[ 1 ] == nil or item[ 2 ] == nil then return item end
  if item[ 3 ] == nil and m.api and m.api.GetContainerItemLink then
    item[ 3 ] = m.api.GetContainerItemLink( item[ 1 ], item[ 2 ] )
  end
  return item
end

function Forged_Mailbox.sendmail_item_is_valid( item )
  if type( item ) ~= "table" then return false end
  local bag, slot = item_bag_slot( item )
  if bag == nil or slot == nil then return false end
  local expected = item_link( item )
  if not expected or expected == "" then
    expected = m.api.GetContainerItemLink( bag, slot )
    item[ 3 ] = expected
  end
  local current = m.api.GetContainerItemLink( bag, slot )
  return current and expected and current == expected
end

function Forged_Mailbox.sendmail_ensure_loaded()
  if m.sendmail_initialized then return true end
  if not (m.api and m.api.SendMailFrame and m.api.SendMailNameEditBox and m.api.SendMailBodyEditBox) then
    return false
  end
  if type( m.sendmail_load ) ~= "function" then return false end
  m.sendmail_load()
  return m.sendmail_initialized and true or false
end

function Forged_Mailbox.set_cod_text()
  local text = string.sub( m.api.COD_AMOUNT, 1, string.len( m.api.COD_AMOUNT ) - 1 )

  text = string.match( text, "^(.-)%s+%S+$" )

  if m.api.SendMailCODAllButton:GetChecked() then
    m.api.SendMailMoneyText:SetText( text .. " " .. L[ "each mail" ] .. ":" )
    m.api.SendMailMoneyText:SetText( text .. " each mail:" )
  else
    m.api.SendMailMoneyText:SetText( text .. " " .. L[ "1st mail" ] .. ":" )
    m.api.SendMailMoneyText:SetText( text .. " 1st mail:" )
  end
end

function Forged_Mailbox.hook.SendMailFrame_Update()
  if not m.sendmail_ensure_loaded() then
    if m.orig and type( m.orig.SendMailFrame_Update ) == "function" then
      return m.orig.SendMailFrame_Update()
    end
    return
  end

  local gap
  local last = m.sendmail_num_attachments()

  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]

    local texture, count
    if btn.item then
      if not m.sendmail_item_is_valid( btn.item ) then
        btn.item = nil
      else
        local bag, slot = item_bag_slot( btn.item )
        texture, count = m.api.GetContainerItemInfo( bag, slot )
      end
    end
    if not texture then
      btn:SetNormalTexture( nil )
      m.api[ btn:GetName() .. "Count" ]:Hide()
      btn.item = nil
    else
      btn:SetNormalTexture( texture )
      if count > 1 then
        m.api[ btn:GetName() .. "Count" ]:Show()
        m.api[ btn:GetName() .. "Count" ]:SetText( count )
      else
        m.api[ btn:GetName() .. "Count" ]:Hide()
      end
    end
  end

  if m.sendmail_num_attachments() > 0 then
    m.api.SendMailCODButton:Enable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if m.sendmail_num_attachments() > 1 and m.api.SendMailCODButton:GetChecked() then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    else
      m.api.SendMailCODAllButton:Disable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
      m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    end
  else
    m.api.SendMailSendMoneyButton:SetChecked( 1 )
    m.api.SendMailCODButton:SetChecked( nil )
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    m.api.SendMailCODButton:Disable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  end

  m.api.MoneyFrame_Update( "SendMailCostMoneyFrame", m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) )

  -- Determine how many rows of attachments to show
  local itemRowCount = 1
  local temp = last
  while temp > ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND do
    itemRowCount = itemRowCount + 1
    temp = temp - ATTACHMENTS_PER_ROW_SEND
  end

  if not gap and temp == ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND then
    itemRowCount = itemRowCount + 1
  end
  if m.api.SendMailFrame.maxRowsShown and last > 0 and itemRowCount < m.api.SendMailFrame.maxRowsShown then
    itemRowCount = m.api.SendMailFrame.maxRowsShown
  else
    m.api.SendMailFrame.maxRowsShown = itemRowCount
  end

  -- Compute sizes
  local cursorx = 0
  local cursory = itemRowCount - 1
  local marginxl = 8 + 6
  local marginxr = 40 + 6
  local areax = m.api.SendMailFrame:GetWidth() - marginxl - marginxr
  local iconx = m.api.MailAttachment1:GetWidth() + 2
  local icony = m.api.MailAttachment1:GetHeight() + 2
  local gapx1 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND)) / (ATTACHMENTS_PER_ROW_SEND - 1) )
  local gapx2 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND) - (gapx1 * (ATTACHMENTS_PER_ROW_SEND - 1))) / 2 )
  local gapy1 = 5
  local gapy2 = 6
  local areay = (gapy2 * 2) + (gapy1 * (itemRowCount - 1)) + (icony * itemRowCount)
  local indentx = marginxl + gapx2 + 17
  local indenty = 170 + gapy2 + icony - 13
  local tabx = (iconx + gapx1) - 3 --this magic number changes the attachment spacing
  local taby = (icony + gapy1)
  local scrollHeight = 249 - areay

  if m.sendmail_bar_left then
    m.sendmail_bar_left:SetPoint( "TOPLEFT", m.api.SendMailFrame, "BOTTOMLEFT", 2 + 15, 184 + areay - 14 )
  end

  m.api.SendMailScrollFrame:SetHeight( scrollHeight )
  m.api.SendMailScrollChildFrame:SetHeight( scrollHeight )

  local SendMailScrollFrameTop = ({ m.api.SendMailScrollFrame:GetRegions() })[ 3 ]
  SendMailScrollFrameTop:SetHeight( scrollHeight )
  SendMailScrollFrameTop:SetTexCoord( 0, .484375, 0, scrollHeight / 256 )

  m.api.StationeryBackgroundLeft:SetHeight( scrollHeight )
  m.api.StationeryBackgroundLeft:SetTexCoord( 0, 1, 0, scrollHeight / 256 )


  m.api.StationeryBackgroundRight:SetHeight( scrollHeight )
  m.api.StationeryBackgroundRight:SetTexCoord( 0, 1, 0, scrollHeight / 256 )

  -- Set Items
  for i = 1, ATTACHMENTS_MAX do
    if cursory >= 0 then
      m.api[ "MailAttachment" .. i ]:Enable()
      m.api[ "MailAttachment" .. i ]:Show()
      m.api[ "MailAttachment" .. i ]:SetPoint( "TOPLEFT", "SendMailFrame", "BOTTOMLEFT", indentx + (tabx * cursorx),
        indenty + (taby * cursory) )

      cursorx = cursorx + 1
      if cursorx >= ATTACHMENTS_PER_ROW_SEND then
        cursory = cursory - 1
        cursorx = 0
      end
    else
      m.api[ "MailAttachment" .. i ]:Hide()
    end
  end

  m.api.SendMailFrame_CanSend()
end

function Forged_Mailbox.hook.SendMailRadioButton_OnClick( index )
  if (index == 1) then
    m.api.SendMailSendMoneyButton:SetChecked( 1 );
    m.api.SendMailCODButton:SetChecked( nil );
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND );
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  else
    m.api.SendMailSendMoneyButton:SetChecked( nil );
    m.api.SendMailCODButton:SetChecked( 1 );
    m.api.SendMailMoneyText:SetText( m.api.COD_AMOUNT );

    if m.sendmail_num_attachments() > 1 then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    end
  end
  m.api.PlaySound( "igMainMenuOptionCheckBoxOn" );
end

function Forged_Mailbox.hook.ClickSendMailItemButton()
  m.sendmail_set_attachment( m.get_cursor_item() )
end

function Forged_Mailbox.hook.GetContainerItemInfo( bag, slot )
  local texture, count, locked, quality, readable, lootable, link = m.orig.GetContainerItemInfo( bag, slot )
  locked = locked or (m.sendmail_attached( bag, slot ) and 1 or nil)
  return texture, count, locked, quality, readable, lootable, link
end

function Forged_Mailbox.hook.PickupContainerItem( bag, slot )
  if m.sendmail_attached( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      return m.sendmail_remove_attachment( { bag, slot } )
    end
    return m.orig.PickupContainerItem( bag, slot )
  end

  if m.api.GetContainerItemInfo( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      m.api.MailFrameTab_OnClick( 2 )
      m.sendmail_set_attachment( { bag, slot } )
      return
    else
      m.set_cursor_item( { bag, slot } )
    end
  end
  return m.orig.PickupContainerItem( bag, slot )
end

function Forged_Mailbox.hook.SplitContainerItem( bag, slot, amount )
  if m.sendmail_attached( bag, slot ) then return end
  return m.orig.SplitContainerItem( bag, slot, amount )
end

function Forged_Mailbox.hook.UseContainerItem( bag, slot, onself )
  if m.sendmail_attached( bag, slot ) then return end
  if m.api.IsShiftKeyDown() or m.api.IsControlKeyDown() or m.api.IsAltKeyDown() then
    return m.orig.UseContainerItem( bag, slot, onself )
  elseif m.api.MailFrame:IsVisible() then
    m.api.MailFrameTab_OnClick( 2 )
    m.sendmail_set_attachment( { bag, slot } )
  elseif m.api.TradeFrame:IsVisible() then
    for i = 1, 6 do
      if not m.api.GetTradePlayerItemLink( i ) then
        m.orig.PickupContainerItem( bag, slot )
        m.api.ClickTradeButton( i )
        return
      end
    end
  else
    return m.orig.UseContainerItem( bag, slot, onself )
  end
end

function Forged_Mailbox.hook.SendMailFrame_CanSend()
  if not m.sendmail_ensure_loaded() then return end

  local button = get_send_button()
  if not button or not button.Enable then return end

  if (not m.sendmail_sending)
      and string.len( m.api.SendMailNameEditBox:GetText() ) > 0
      and (m.api.SendMailSendMoneyButton:GetChecked() and m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ) or 0)
        + m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) <= m.api.GetMoney() then
    button:Enable()
  else
    button:Disable()
  end
end

function Forged_Mailbox.send_mail_button_onclick()
  if m.api.MailAutoCompleteBox then
    m.api.MailAutoCompleteBox:Hide()
  end

  m.api.Forged_Mailbox_To = m.api.SendMailNameEditBox:GetText()
  m.api.SendMailNameEditBox:HighlightText()

  m.sendmail_state = {
    to = m.api.Forged_Mailbox_To,
    subject = (m.api.SendMailSubjectEditBox and m.api.SendMailSubjectEditBox.GetText and m.api.SendMailSubjectEditBox:GetText()) or "",
    body = m.api.SendMailBodyEditBox:GetText(),
    money = m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ),
    cod = m.api.SendMailCODButton:GetChecked(),
    attachments = m.sendmail_attachments(),
    numMessages = math.max( 1, m.sendmail_num_attachments() ),
  }

  m.sendmail_clear()
  m.sendmail_sending = true
  m.sendmail_send()
end

function Forged_Mailbox.sendmail_load()
  if m.sendmail_initialized then return end
  if not (m.api and m.api.SendMailFrame and m.api.SendMailNameEditBox and m.api.SendMailBodyEditBox) then
    return
  end

  m.api.SendMailFrame:EnableMouse( false )

  -- Ensure attachment buttons exist (some UIs/lazy-load setups may not have created them yet).
  for i = 1, ATTACHMENTS_MAX do
    local name = "MailAttachment" .. i
    local btn = m.api[ name ]
    if not btn then
      btn = m.api.CreateFrame( "Button", name, m.api.SendMailFrame, nil )
      btn:SetWidth( 37 )
      btn:SetHeight( 37 )
      btn:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
      btn:RegisterForDrag( "LeftButton" )
      btn:SetHighlightTexture( "Interface\\Buttons\\ButtonHilight-Square", "ADD" )
      btn:SetScript( "OnReceiveDrag", m.attachment_button_on_click )
      btn:SetScript( "OnDragStart", m.attachment_button_on_click )
      btn:SetScript( "OnClick", function()
        m.attachment_button_on_click()
        local onEnter = this:GetScript( "OnEnter" )
        if onEnter then onEnter() end
      end )
      btn:SetScript( "OnEnter", function()
        m.api.GameTooltip:SetOwner( this, "ANCHOR_RIGHT" )
        if this.item then
          local bag, slot = item_bag_slot( this.item )
          if bag and slot then
            m.api.GameTooltip:SetBagItem( bag, slot )
          end
        else
          m.api.GameTooltip:SetText( m.api.ATTACHMENT_TEXT or "Attachment", 1.0, 1.0, 1.0 )
        end
      end )
      btn:SetScript( "OnLeave", function() m.api.GameTooltip:Hide() end )

      local count = btn:CreateFontString( name .. "Count", "ARTWORK", "NumberFontNormal" )
      count:SetJustifyH( "RIGHT" )
      count:ClearAllPoints()
      count:SetPoint( "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 2 )
      count:Hide()

      local bg = btn:CreateTexture( nil, "BACKGROUND" )
      bg:SetTexture( "Interface\\Buttons\\UI-Slot-Background" )
      bg:SetWidth( 39 )
      bg:SetHeight( 39 )
      bg:SetPoint( "TOPLEFT", btn, "TOPLEFT", -1, 1 )
      bg:SetTexCoord( 0, 0.640625, 0, 0.640625 )
    end
  end

  m.sendmail_bar_left = m.sendmail_bar_left or m.api.SendMailFrame:CreateTexture( nil, "BACKGROUND" )
  m.sendmail_bar_left:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.sendmail_bar_left:SetWidth( 256 )
  m.sendmail_bar_left:SetHeight( 16 )
  m.sendmail_bar_left:SetTexCoord( 0, 1, 0, .25 )

  m.sendmail_bar_right = m.sendmail_bar_right or m.api.SendMailFrame:CreateTexture( nil, "BACKGROUND" )
  m.sendmail_bar_right:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.sendmail_bar_right:SetWidth( 75 )
  m.sendmail_bar_right:SetHeight( 16 )
  m.sendmail_bar_right:SetTexCoord( 0, .29296875, .25, .5 )
  m.sendmail_bar_right:ClearAllPoints()
  m.sendmail_bar_right:SetPoint( "LEFT", m.sendmail_bar_left, "RIGHT" )

  m.api.SendMailMoneyText:SetJustifyH( "LEFT" )
  m.api.SendMailMoneyText:SetPoint( "TOPLEFT", 0, 0 )
  m.api.SendMailMoney:ClearAllPoints()
  m.api.SendMailMoney:SetPoint( "TOPLEFT", m.api.SendMailMoneyText, "BOTTOMLEFT", 5, -5 )
  m.api.SendMailMoneyGoldRight:SetPoint( "RIGHT", 20, 0 )
  do ({ m.api.SendMailMoneyGold:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneyGold:SetMaxLetters( 7 )
  m.api.SendMailMoneyGold:SetWidth( 50 )
  m.api.SendMailMoneySilverRight:SetPoint( "RIGHT", 10, 0 )
  do ({ m.api.SendMailMoneySilver:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneySilver:SetWidth( 28 )
  m.api.SendMailMoneySilver:SetPoint( "LEFT", m.api.SendMailMoneyGold, "RIGHT", 30, 0 )
  m.api.SendMailMoneyCopperRight:SetPoint( "RIGHT", 10, 0 )
  do ({ m.api.SendMailMoneyCopper:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneyCopper:SetWidth( 28 )
  m.api.SendMailMoneyCopper:SetPoint( "LEFT", m.api.SendMailMoneySilver, "RIGHT", 20, 0 )
  m.api.SendMailSendMoneyButton:SetPoint( "TOPLEFT", m.api.SendMailMoney, "TOPRIGHT", 0, 12 )

  -- Override send button click to drive multi-mail sending logic.
  m.api.SendMailMailButton_OnClick = m.send_mail_button_onclick

  m.api.SendMailNameEditBox._SetText = m.api.SendMailNameEditBox.SetText
  function m.api.SendMailNameEditBox:SetText( text )
    if not m.api.Forged_Mailbox_To then
      return self:_SetText( text )
    end
  end

  m.api.SendMailNameEditBox:SetScript( "OnShow", function()
    if m.api.Forged_Mailbox_To then
      m.api.this:_SetText( m.api.Forged_Mailbox_To )
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnChar", function()
    m.api.Forged_Mailbox_To = nil
    GetSuggestions()
  end )
  m.api.SendMailNameEditBox:SetScript( "OnTabPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      if m.api.IsShiftKeyDown() then
        m.previous_match()
      else
        m.next_match()
      end
    else
      if m.api.SendMailSubjectEditBox then
        m.api.SendMailSubjectEditBox:SetFocus()
      end
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEnterPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
      this:HighlightText( 0, 0 )
    else
      if m.api.SendMailSubjectEditBox then
        m.api.SendMailSubjectEditBox:SetFocus()
      end
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEscapePressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
    else
      this:ClearFocus()
    end
  end )
  function m.api.SendMailNameEditBox.focusLoss()
    m.api.MailAutoCompleteBox:Hide()
  end

  m.api.SendMailCODAllButtonText:SetText( "  All mails" )
  m.api.SendMailCODAllButton:SetScript( "OnClick", m.set_cod_text )

  do
    local orig_script = m.api.SendMailNameEditBox:GetScript( "OnTextChanged" )
    m.api.SendMailNameEditBox:SetScript( "OnTextChanged", function()
      local text = this:GetText()
      local formatted = string.gsub( string.lower( text ), "^%l", string.upper )
      if text ~= formatted then
        this:SetText( formatted )
      end
      return orig_script()
    end )
  end

  for _, editBox in { m.api.SendMailNameEditBox, m.api.SendMailSubjectEditBox } do
    editBox:SetScript( "OnEditFocusGained", function()
      this:HighlightText()
    end )
    editBox:SetScript( "OnEditFocusLost", function()
      (this.focusLoss or function() end)()
      this:HighlightText( 0, 0 )
    end )
    do
      local lastClick
      editBox:SetScript( "OnMouseDown", function()
        local x, y = m.api.GetCursorPosition()
        if lastClick and m.api.GetTime() - lastClick.t < .5 and x == lastClick.x and y == lastClick.y then
          this:SetScript( "OnUpdate", function()
            this:HighlightText()
            this:SetScript( "OnUpdate", nil )
          end )
        end
        lastClick = { t = m.api.GetTime(), x = x, y = y }
      end )
    end
  end

  m.sendmail_initialized = true
end

--@param bag number
--@param slot number
function Forged_Mailbox.sendmail_attached( bag, slot )
  if not (m.api and m.api.MailFrame and m.api.MailFrame.IsVisible) then return false end
  if not m.api.MailFrame:IsVisible() then return false end
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item and btn.item[ 1 ] == bag and btn.item[ 2 ] == slot then
      return true
    end
  end
  if m.sendmail_state then
    for _, attachment in ipairs( m.sendmail_state.attachments or {} ) do
      if attachment and attachment[ 1 ] == bag and attachment[ 2 ] == slot then
        return true
      end
    end
  end
end

function Forged_Mailbox.attachment_button_on_click()
  local attachedItem = this.item
  local cursorItem = m.get_cursor_item()
  ensure_item_link( cursorItem )
  if m.sendmail_set_attachment( cursorItem, this ) then
    if attachedItem then
      if arg1 == "LeftButton" then m.set_cursor_item( attachedItem ) end
      local bag, slot = item_bag_slot( attachedItem )
      if bag and slot then
        m.orig.PickupContainerItem( bag, slot )
      end
      if arg1 ~= "LeftButton" then m.api.ClearCursor() end -- for the lock changed event
    end
  end
end

function Forged_Mailbox.sendmail_remove_attachment( item )
  if not item then return end
  if type( item ) == "table" and m.sendmail_attached( item[ 1 ], item[ 2 ] ) then
    for i = 1, ATTACHMENTS_MAX do
      local btn = m.api[ "MailAttachment" .. i ]
      if btn.item and btn.item[ 1 ] == item[ 1 ] and btn.item[ 2 ] == item[ 2 ] then
        m.api[ "MailAttachment" .. i ].item = nil
        m.orig.PickupContainerItem( item[ 1 ], item[ 2 ] )
        m.api.ClearCursor()
        m.api.SendMailFrame_Update()
        return
      end
    end
  end
end

-- requires an item lock changed event for a proper update
---@param item table
---@param slot number?
function Forged_Mailbox.sendmail_set_attachment( item, slot )
  if item and not m.sendmail_pickup_mailable( item ) then
    m.api.ClearCursor()
    return
  elseif not slot then
    for i = 1, ATTACHMENTS_MAX do
      if not m.api[ "MailAttachment" .. i ].item then
        slot = m.api[ "MailAttachment" .. i ]
        break
      end
    end
  end
  if slot then
    if not (item or slot.item) then return true end
    slot.item = ensure_item_link( item )
    m.api.ClearCursor()
    m.api.SendMailFrame_Update()
    return true
  end
end

---@param item table
function Forged_Mailbox.sendmail_pickup_mailable( item )
  ensure_item_link( item )
  m.api.ClearCursor()
  m.orig.ClickSendMailItemButton()
  m.api.ClearCursor()
  local bag, slot = item_bag_slot( item )
  if bag and slot then
    m.orig.PickupContainerItem( bag, slot )
  end
  m.orig.ClickSendMailItemButton()
  local mailable = m.api.GetSendMailItem() and true or false
  m.orig.ClickSendMailItemButton()
  return mailable
end

function Forged_Mailbox.sendmail_num_attachments()
  local x = 0
  for i = 1, ATTACHMENTS_MAX do
    if m.api[ "MailAttachment" .. i ].item then
      x = x + 1
    end
  end
  return x
end

function Forged_Mailbox.sendmail_attachments()
  local t = {}
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item then
      table.insert( t, btn.item )
    end
  end
  return t
end

function Forged_Mailbox.sendmail_clear()
  local anyItem
  for i = 1, ATTACHMENTS_MAX do
    anyItem = anyItem or m.api[ "MailAttachment" .. i ].item
    m.api[ "MailAttachment" .. i ].item = nil
  end
  if anyItem then
    m.api.ClearCursor()
    local bag, slot = item_bag_slot( anyItem )
    if bag and slot then
      m.orig.PickupContainerItem( bag, slot )
    end
    m.api.ClearCursor()
  end
  do
    local button = get_send_button()
    if button and button.Disable then button:Disable() end
  end
  m.api.SendMailNameEditBox:SetText ""
  m.api.SendMailNameEditBox:SetFocus()
  if m.api.SendMailSubjectEditBox then
    m.api.SendMailSubjectEditBox:SetText( "" )
  end
  m.api.SendMailBodyEditBox:SetText ""
  m.api.MoneyInputFrame_ResetMoney( m.api.SendMailMoney )
  m.api.SendMailRadioButton_OnClick( 1 )

  m.api.SendMailFrame_Update()
end

function Forged_Mailbox.sendmail_send()
  local item = table.remove( m.sendmail_state.attachments, 1 )
  if item then
    ensure_item_link( item )
    if not m.sendmail_item_is_valid( item ) then
      m.sendmail_sending = false
      m.sendmail_state = nil
      m.api.ClearCursor()
      m.orig.ClickSendMailItemButton()
      m.api.ClearCursor()
      m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473Forged_Mailbox|r: Attachment moved/changed; sending cancelled.", 1, 0, 0 )
      return
    end
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
    m.orig.PickupContainerItem( item[ 1 ], item[ 2 ] )
    m.orig.ClickSendMailItemButton()

    if not m.api.GetSendMailItem() then
      m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473Forged_Mailbox|r: " .. m.api.ERROR_CAPS, 1, 0, 0 )
      return
    end
  end

  local amount = m.sendmail_state.money
  m.sendmail_state.sent_money = m.sendmail_state.money
  m.sendmail_state.sent = false

  if amount > 0 then
    if not m.api.SendMailCODAllButton:GetChecked() then
      m.sendmail_state.money = 0
    end
    if m.sendmail_state.cod then
      m.sendmail_state.cod = amount
      m.api.SetSendMailCOD( amount )
    else
      m.sendmail_state.money = 0
      m.api.SetSendMailMoney( amount )
    end
  end

  local subject = m.sendmail_state.subject
  if subject == "" then
    if item then
      local item_name, texture, stack_count = m.api.GetSendMailItem()
      subject = item_name .. (stack_count > 1 and " (" .. stack_count .. ")" or "")
      m.sendmail_state.item = item_name
      m.sendmail_state.icon = texture
    else
      subject = "<" .. m.api.NO_ATTACHMENTS .. ">"
    end
  elseif m.sendmail_state.numMessages > 1 then
    subject = subject .. string.format( " [%d/%d]", m.sendmail_state.numMessages - getn( m.sendmail_state.attachments ),
      m.sendmail_state.numMessages )
  end

  m.sendmail_state.sent_subject = subject

  m.debug( "SendMail" )
  m.api.SendMail( m.sendmail_state.to, subject, m.sendmail_state.body )

  if getn( m.sendmail_state.attachments ) == 0 then
    m.sendmail_sending = false
  end
end

-- Mark send-mail UI as initialized once load finishes successfully.
