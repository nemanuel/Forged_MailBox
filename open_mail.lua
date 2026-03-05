local m = Forged_Mailbox

function Forged_Mailbox.MAIL_INBOX_UPDATE()
  if m.inbox_opening then
    m.inbox_update = true
  end

  for i = 1, 7 do
    local index = (i + (m.api.InboxFrame.pageNum - 1) * 7)
    if index <= m.api.GetInboxNumItems() then
      local _, _, _, _, _, _, _, _, _, was_returned = m.api.GetInboxHeaderInfo( index )
      if was_returned then
        m.api[ "Forged_MailboxReturnedArrow" .. i ]:Show()
      else
        m.api[ "Forged_MailboxReturnedArrow" .. i ]:Hide()
      end
    end
  end
end

function Forged_Mailbox.inbox_load()
  m.api.InboxFrame:EnableMouse( false )
  local btn = m.api.CreateFrame( "Button", "Forged_MailboxOpenMailButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btn:SetPoint( "BOTTOM", -10, 90 )
  btn:SetText( m.api.OPENMAIL )
  btn:SetWidth( math.max( 120, 30 + ({ btn:GetRegions() })[ 1 ]:GetStringWidth() ) )
  btn:SetHeight( 25 )
  btn:SetScript( "OnClick", m.inbox_open_all )

  for i = 1, 7 do
    m.api[ "Forged_MailboxReturnedArrow" .. i .. "Texture" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
  end
end

function Forged_Mailbox.inbox_open_all()
  m.inbox_opening = true
  m.inbox_update_lock()
  m.inbox_skip = false
  m.inbox_index = 1
  m.inbox_update = true
end

function Forged_Mailbox.inbox_abort()
  m.inbox_opening = false
  m.inbox_update_lock()
  m.inbox_update = false
end

---@param money number
function Forged_Mailbox.update_money( money )
  m.money_received = m.money_received + money
  m.api.MoneyReceived:SetText( "Money received: " .. m.format_money( m.money_received ) )

  if m.money_received > 0 then
    m.api.MoneyReceived:Show()
  else
    m.api.MoneyReceived:Hide()
  end
end

---@param i number
---@param manual boolean?
function Forged_Mailbox.inbox_open( i, manual )
  m.debug( "inbox_open" )
  m.inbox_open_in_progress = true
  local package_icon, _, sender, subject, money, cod, days_left, has_item, read, returned, _, _, gm = m.api.GetInboxHeaderInfo( i )

  -- Track & ledger money immediately for open-all (money-only mails like AH sales).
  if (not manual) and money and money > 0 then
    m.update_money( money )
    local entry = {
      from = sender,
      subject = subject,
      money = money,
      cod = cod,
      days_left = days_left,
      returned = returned,
      gm = gm,
      icon = package_icon,
      item = has_item and m.api.GetInboxItem( i ) or nil,
    }
    if m.log and m.log.add then m.log.add( "Received", entry ) end
    if m.ledger and m.ledger.add then m.ledger.add( "Received", entry ) end
  end

  if has_item then
    if not m.received_icon then
      m.received_item = m.api.GetInboxItem( i )
      m.received_icon = package_icon
    end
  end

  if (read and not has_item) or manual then
    if manual and money > 0 then
      m.update_money( money )
      m.received_money = money
    end
    if money == 0 or manual then
      local entry = {
        from = sender,
        subject = subject,
        money = manual and money or m.received_money,
        cod = cod,
        days_left = days_left,
        returned = returned,
        gm = gm,
        icon = m.received_icon,
        item = m.received_item
      }
      if m.log and m.log.add then m.log.add( "Received", entry ) end
      if m.ledger and m.ledger.add then m.ledger.add( "Received", entry ) end
      m.received_money = 0
      m.received_icon = nil
      m.received_item = nil
    end
  end

  m.api.GetInboxText( i )
  m.TakeInboxMoney( i )
  m.TakeInboxItem( i )
  m.DeleteInboxItem( i )

  m.inbox_open_in_progress = false
end

function Forged_Mailbox.inbox_update_lock()
  for i = 1, 7 do
    m.api[ "MailItem" .. i .. "ButtonIcon" ]:SetDesaturated( m.inbox_opening )
    if m.inbox_opening then
      m.api[ "MailItem" .. i .. "Button" ]:SetChecked( nil )
    end
  end
end

function Forged_Mailbox.hook.GetInboxHeaderInfo( ... )
  local sender, canReply = arg[ 3 ], arg[ 12 ]
  if sender and canReply then
    m.add_auto_complete_name( sender )
  end

  return m.orig.GetInboxHeaderInfo( unpack( arg ) )
end

function Forged_Mailbox.hook.TakeInboxMoney( index )
  local package_icon, _, sender, subject, money, cod, days_left, has_item, _, returned, _, _, gm = m.api.GetInboxHeaderInfo( index )
  if money and money > 0 then
    m.took_money_for = m.took_money_for or {}
    m.took_money_for[ index ] = true

    local entry = {
      from = sender,
      subject = subject,
      money = money,
      cod = cod,
      days_left = days_left,
      returned = returned,
      gm = gm,
      icon = package_icon,
      item = has_item and m.api.GetInboxItem( index ) or nil,
    }
    -- If the player uses the default mail UI (open mail -> Take Money),
    -- we still want expanded ledger rows to have per-mail money values.
    -- Avoid duplicates when our open-all / right-click-open flow already logged it.
    if (not m.inbox_open_in_progress) and (not m.inbox_opening) then
      if m.log and m.log.add then m.log.add( "Received", entry ) end
    end
    if m.ledger and m.ledger.add then m.ledger.add( "Received", entry ) end
  end

  return m.orig.TakeInboxMoney( index )
end

function Forged_Mailbox.hook.OpenMail_Reply( ... )
  m.api.Forged_Mailbox_To = nil
  return m.orig.OpenMail_Reply( unpack( arg ) )
end

function Forged_Mailbox.hook.InboxFrame_Update()
  m.orig.InboxFrame_Update()
  for i = 1, 7 do
    -- hack for tooltip update
    m.api[ "MailItem" .. i ]:Hide()
    m.api[ "MailItem" .. i ]:Show()
  end

  local currentPage = m.api.InboxFrame.pageNum
  local totalPages = math.ceil( m.api.GetInboxNumItems() / m.api.INBOXITEMS_TO_DISPLAY )
  local text = totalPages > 0 and (currentPage .. "/" .. totalPages) or m.api.EMPTY
  m.api.InboxTitleText:SetText( m.api.INBOX .. " [" .. text .. "]" )

  m.inbox_update_lock()
end

---@param i number
function Forged_Mailbox.hook.InboxFrame_OnClick( i )
  if m.inbox_opening or arg1 == "RightButton" and ({ m.api.GetInboxHeaderInfo( i ) })[ 6 ] > 0 then
    this:SetChecked( nil )
  elseif arg1 == "RightButton" then
    m.inbox_open( i, true )
  else
    return m.orig.InboxFrame_OnClick( i )
  end
end

function Forged_Mailbox.hook.InboxFrameItem_OnEnter()
  m.orig.InboxFrameItem_OnEnter()
  if m.api.GetInboxItem( this.index ) then
    m.api.GameTooltip:AddLine( m.api.ITEM_OPENABLE, "", 0, 1, 0 )
    m.api.GameTooltip:Show()
  end
end

function Forged_Mailbox.hook.OpenMailFrame_OnHide()
  if m.api.InboxFrame.openMailID then
    if m.took_money_for and m.took_money_for[ m.api.InboxFrame.openMailID ] then
      m.took_money_for[ m.api.InboxFrame.openMailID ] = nil
      m.orig.OpenMailFrame_OnHide()
      return
    end

    local package_icon, _, sender, subject, money, cod, days_left, itemID, _, returned, text_created, _, gm = m.api.GetInboxHeaderInfo( m.api.InboxFrame.openMailID )
    if (money == 0 and not itemID and text_created) then
      local received_item = m.api.GetInboxItem( m.api.InboxFrame.openMailID )
      local entry = {
        from = sender,
        subject = subject,
        money = money,
        cod = cod,
        days_left = days_left,
        returned = returned,
        gm = gm,
        icon = package_icon,
        item = received_item
      }
      if m.log and m.log.add then m.log.add( "Received", entry ) end
      if m.ledger and m.ledger.add then m.ledger.add( "Received", entry ) end
    end
  else
    m.debug( "returning mail" )
  end

  m.orig.OpenMailFrame_OnHide()
end
