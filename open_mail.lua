local m = Forged_Mailbox

local function ensure_open_confirm_dialogs()
    if not m.api then
        return
    end

    local dialogs = m.api.StaticPopupDialogs
    if type(dialogs) ~= "table" then
        return
    end

    if not dialogs.FORGED_MAILBOX_OPEN_ALL_MAIL then
        dialogs.FORGED_MAILBOX_OPEN_ALL_MAIL = {
            text = "Are you sure you want to open all mail?",
            button1 = m.api.YES or "Yes",
            button2 = m.api.NO or "No",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            OnAccept = function()
                if Forged_Mailbox and Forged_Mailbox.inbox_open_all then
                    Forged_Mailbox.inbox_open_all()
                end
            end
        }
    end

    if not dialogs.FORGED_MAILBOX_OPEN_ALL_AUCTION_MAIL then
        dialogs.FORGED_MAILBOX_OPEN_ALL_AUCTION_MAIL = {
            text = "Are you sure you want to open all sold auction mail?",
            button1 = m.api.YES or "Yes",
            button2 = m.api.NO or "No",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            OnAccept = function()
                if Forged_Mailbox and Forged_Mailbox.inbox_open_auction_all then
                    Forged_Mailbox.inbox_open_auction_all()
                end
            end
        }
    end
end

function Forged_Mailbox.inbox_confirm_open_all()
    ensure_open_confirm_dialogs()
    if m.api and m.api.StaticPopup_Show then
        m.api.StaticPopup_Show("FORGED_MAILBOX_OPEN_ALL_MAIL")
    end
end

function Forged_Mailbox.inbox_confirm_open_auction_all()
    ensure_open_confirm_dialogs()
    if m.api and m.api.StaticPopup_Show then
        m.api.StaticPopup_Show("FORGED_MAILBOX_OPEN_ALL_AUCTION_MAIL")
    end
end

local function is_auction_mail(sender, subject)
    if not m.api then
        return false
    end

    -- Only treat SUCCESSFUL auction sales as "auction mail" for the Open Auction Mail button.
    -- Do NOT match by sender ("Auction House"), because that would include outbid/won/expired/etc.
    if type(subject) ~= "string" or subject == "" then
        return false
    end

    local pattern = m.api.AUCTION_SOLD_MAIL_SUBJECT
    if type(pattern) ~= "string" or pattern == "" then
        return false
    end

    local stem = string.gsub(pattern, "%%s", "")
    if stem == "" then
        return false
    end

    return string.find(subject, stem, 1, true) ~= nil
end

function Forged_Mailbox.inbox_is_auction_mail(sender, subject)
    return is_auction_mail(sender, subject)
end

function Forged_Mailbox.MAIL_INBOX_UPDATE()
    if m.inbox_opening then
        m.inbox_update = true
    end

    for i = 1, 7 do
        local index = (i + (m.api.InboxFrame.pageNum - 1) * 7)
        if index <= m.api.GetInboxNumItems() then
            local _, _, _, _, _, _, _, _, _, was_returned = m.api.GetInboxHeaderInfo(index)
            if was_returned then
                m.api["Forged_MailboxReturnedArrow" .. i]:Show()
            else
                m.api["Forged_MailboxReturnedArrow" .. i]:Hide()
            end
        end
    end
end

function Forged_Mailbox.inbox_load()
    m.api.InboxFrame:EnableMouse(false)
    local btn = m.api.CreateFrame("Button", "Forged_MailboxOpenMailButton", m.api.InboxFrame, "UIPanelButtonTemplate")
    btn:ClearAllPoints()
    btn:SetPoint("TOP", m.api.InboxFrame, "TOP", -42, -46)
    btn:SetText("Open Mail")
    btn:SetWidth(86)
    btn:SetHeight(25)
    btn:SetScript("OnClick", m.inbox_confirm_open_all)

    local btn_auction = m.api.CreateFrame("Button", "Forged_MailboxOpenAuctionMailButton", m.api.InboxFrame,
        "UIPanelButtonTemplate")
    btn_auction:ClearAllPoints()
    btn_auction:SetPoint("LEFT", btn, "RIGHT", 4, 0)
    btn_auction:SetText("Open Sold Auction Mail")
    btn_auction:SetWidth(136)
    btn_auction:SetHeight(25)
    btn_auction:SetScript("OnClick", m.inbox_confirm_open_auction_all)

    for i = 1, 7 do
        m.api["Forged_MailboxReturnedArrow" .. i .. "Texture"]:SetVertexColor(m.api.NORMAL_FONT_COLOR.r,
            m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b)
    end
end

function Forged_Mailbox.inbox_open_all()
    m.inbox_open_filter = nil
    m.inbox_opening = true
    m.inbox_update_lock()
    m.inbox_skip = false
    m.inbox_index = 1
    m.inbox_update = true
end

function Forged_Mailbox.inbox_open_auction_all()
    m.inbox_open_filter = "auction"
    m.inbox_opening = true
    m.inbox_update_lock()
    m.inbox_skip = false
    m.inbox_index = 1
    m.inbox_update = true
end

function Forged_Mailbox.inbox_abort()
    m.inbox_opening = false
    m.inbox_open_filter = nil
    m.inbox_update_lock()
    m.inbox_update = false
end

---@param i number
---@param manual boolean?
function Forged_Mailbox.inbox_open(i, manual)
    m.debug("inbox_open")
    m.inbox_open_in_progress = true
    local package_icon, _, sender, subject, money, cod, days_left, has_item, read, returned, _, _, gm = m.api
                                                                                                            .GetInboxHeaderInfo(
        i)

    -- Track & ledger money immediately for open-all (money-only mails like AH sales).
    if (not manual) and money and money > 0 then
        local entry = {
            from = sender,
            subject = subject,
            money = money,
            cod = cod,
            days_left = days_left,
            returned = returned,
            gm = gm,
            icon = package_icon,
            item = has_item and m.api.GetInboxItem(i) or nil
        }
        if m.log and m.log.add then
            m.log.add("Received", entry)
        end
        if m.ledger and m.ledger.add then
            m.ledger.add("Received", entry)
        end
    end

    if has_item then
        if not m.received_icon then
            m.received_item = m.api.GetInboxItem(i)
            m.received_icon = package_icon
        end
    end

    if (read and not has_item) or manual then
        if manual and money > 0 then
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
            if m.log and m.log.add then
                m.log.add("Received", entry)
            end
            if m.ledger and m.ledger.add then
                m.ledger.add("Received", entry)
            end
            m.received_money = 0
            m.received_icon = nil
            m.received_item = nil
        end
    end

    m.api.GetInboxText(i)
    m.TakeInboxMoney(i)
    m.TakeInboxItem(i)
    m.DeleteInboxItem(i)

    m.inbox_open_in_progress = false
end

function Forged_Mailbox.inbox_update_lock()
    for i = 1, 7 do
        m.api["MailItem" .. i .. "ButtonIcon"]:SetDesaturated(m.inbox_opening)
        if m.inbox_opening then
            m.api["MailItem" .. i .. "Button"]:SetChecked(nil)
        end
    end
end

function Forged_Mailbox.hook.GetInboxHeaderInfo(...)
    local sender, canReply = arg[3], arg[12]
    if sender and canReply then
        m.add_auto_complete_name(sender)
    end

    return m.orig.GetInboxHeaderInfo(unpack(arg))
end

function Forged_Mailbox.hook.TakeInboxMoney(index)
    local package_icon, _, sender, subject, money, cod, days_left, has_item, _, returned, _, _, gm = m.api
                                                                                                         .GetInboxHeaderInfo(
        index)
    if money and money > 0 then
        m.took_money_for = m.took_money_for or {}
        m.took_money_for[index] = true

        local entry = {
            from = sender,
            subject = subject,
            money = money,
            cod = cod,
            days_left = days_left,
            returned = returned,
            gm = gm,
            icon = package_icon,
            item = has_item and m.api.GetInboxItem(index) or nil
        }
        -- If the player uses the default mail UI (open mail -> Take Money),
        -- we still want expanded ledger rows to have per-mail money values.
        -- Avoid duplicates when our open-all / right-click-open flow already logged it.
        if (not m.inbox_open_in_progress) and (not m.inbox_opening) then
            if m.log and m.log.add then
                m.log.add("Received", entry)
            end
        end
        if m.ledger and m.ledger.add then
            m.ledger.add("Received", entry)
        end
    end

    return m.orig.TakeInboxMoney(index)
end

function Forged_Mailbox.hook.OpenMail_Reply(...)
    m.api.Forged_Mailbox_To = nil
    return m.orig.OpenMail_Reply(unpack(arg))
end

function Forged_Mailbox.hook.InboxFrame_Update()
    m.orig.InboxFrame_Update()
    for i = 1, 7 do
        -- hack for tooltip update
        m.api["MailItem" .. i]:Hide()
        m.api["MailItem" .. i]:Show()
    end

    local currentPage = m.api.InboxFrame.pageNum
    local totalPages = math.ceil(m.api.GetInboxNumItems() / m.api.INBOXITEMS_TO_DISPLAY)
    local text = totalPages > 0 and (currentPage .. "/" .. totalPages) or m.api.EMPTY
    m.api.InboxTitleText:SetText(m.api.INBOX .. " [" .. text .. "]")

    m.inbox_update_lock()
end

---@param i number
function Forged_Mailbox.hook.InboxFrame_OnClick(i)
    if m.inbox_opening or arg1 == "RightButton" and ({m.api.GetInboxHeaderInfo(i)})[6] > 0 then
        this:SetChecked(nil)
    elseif arg1 == "RightButton" then
        m.inbox_open(i, true)
    else
        return m.orig.InboxFrame_OnClick(i)
    end
end

function Forged_Mailbox.hook.InboxFrameItem_OnEnter()
    m.orig.InboxFrameItem_OnEnter()
    if m.api.GetInboxItem(this.index) then
        m.api.GameTooltip:AddLine(m.api.ITEM_OPENABLE, "", 0, 1, 0)
        m.api.GameTooltip:Show()
    end
end

function Forged_Mailbox.hook.OpenMailFrame_OnHide()
    if m.api.InboxFrame.openMailID then
        if m.took_money_for and m.took_money_for[m.api.InboxFrame.openMailID] then
            m.took_money_for[m.api.InboxFrame.openMailID] = nil
            m.orig.OpenMailFrame_OnHide()
            return
        end

        local package_icon, _, sender, subject, money, cod, days_left, itemID, _, returned, text_created, _, gm = m.api
                                                                                                                      .GetInboxHeaderInfo(
            m.api.InboxFrame.openMailID)
        if (money == 0 and not itemID and text_created) then
            local received_item = m.api.GetInboxItem(m.api.InboxFrame.openMailID)
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
            if m.log and m.log.add then
                m.log.add("Received", entry)
            end
            if m.ledger and m.ledger.add then
                m.ledger.add("Received", entry)
            end
        end
    else
        m.debug("returning mail")
    end

    m.orig.OpenMailFrame_OnHide()
end
