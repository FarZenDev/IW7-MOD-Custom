-- EasyMP friends menu: host a game, see friends status, join them, accept invites
-- structure based on ModSelectMenu

local easyMPPath = "frontEnd.EasyMPFriends"

easyMPFriendsCleanup = function()
    WipeGlobalModelsAtPath(easyMPPath)
end

local leaveMenu = function(menuElement, controllerIndex)
    LUI.FlowManager.RequestLeaveMenu(menuElement)
end

local updateInfoPanel = function(menuElement)
    local scopedData = LUI.FlowManager.GetScopedData(menuElement)
    if not scopedData.currentLabel then
        scopedData.currentLabel = ""
    end
    if not scopedData.currentDesc then
        scopedData.currentDesc = ""
    end

    menuElement:processEvent({
        name = "menu_refresh"
    })
    local currentMenu = menuElement:GetCurrentMenu()
    if currentMenu.InfoTitle then
        currentMenu.InfoTitle:setText(scopedData.currentLabel)
    end
    if currentMenu.InfoText then
        currentMenu.InfoText:setText(scopedData.currentDesc)
    end
end

local onRowHover = function(menuElement, controllerIndex, rowData)
    local scopedData = LUI.FlowManager.GetScopedData(menuElement)
    scopedData.currentLabel = rowData.infoTitle or ""
    scopedData.currentDesc = rowData.infoDesc or ""
    -- remember which friend is highlighted, for the Supprimer / Renommer actions
    menuElement.selectedFriend = rowData.friendName
    updateInfoPanel(menuElement)
end

-- confirmation popup (Rejoindre X ?) reused from the game's generic yes/no popup
EasyMPConfirmData = nil

function EasyMPConfirmPopup(menu, controller)
    local self = LUI.UIElement.new()
    self.id = "EasyMPConfirmPopup"
    self:registerAnimationState("default", {
        topAnchor = true,
        leftAnchor = true,
        bottomAnchor = true,
        rightAnchor = true,
        top = -50,
        left = 0,
        bottom = 0,
        right = 0,
        alpha = 1,
    })
    self:animateToState("default", 0)
    local data = EasyMPConfirmData or {}
    MenuBuilder.BuildAddChild(self, {
        type = "generic_yesno_popup",
        id = "easymp_confirm_popup_id",
        properties = {
            message_text_alignment = LUI.Alignment.Center,
            message_text = data.message or "",
            popup_title = data.title or "",
            padding_top = 12,
            yes_action = function()
                if EasyMPConfirmData and EasyMPConfirmData.action then
                    EasyMPConfirmData.action()
                end
            end,
        },
    })
    return self
end
MenuBuilder.registerType("EasyMPConfirmPopup", EasyMPConfirmPopup)

-- ask "Rejoindre X ?" before actually connecting
local function confirmJoin(controller, friendName, joinCommand)
    EasyMPConfirmData = {
        message = "Rejoindre " .. friendName .. " ?",
        title = "JOUER ENTRE AMIS",
        action = function()
            Engine.Exec(joinCommand)
        end,
    }
    -- if the popup can't be shown for any reason, fall back to joining directly
    local ok = pcall(function()
        LUI.FlowManager.RequestPopupMenu(nil, "EasyMPConfirmPopup", true, controller, false)
    end)
    if not ok then
        Engine.Exec(joinCommand)
    end
end

local buildRows = function()
    local rows = {}

    local invite = friendslist.getinvite()
    if invite.valid then
        rows[#rows + 1] = {
            label = "^2>> INVITATION DE " .. ToUpperCase(invite.from) .. " <<",
            infoTitle = "Invitation de " .. invite.from,
            infoDesc = "Partie " .. (invite.gametype ~= "" and invite.gametype or "?") .. " sur " ..
                (invite.mapname ~= "" and invite.mapname or "?") .. " - cliquez pour rejoindre !",
            onClick = function(element, eventArgs)
                confirmJoin(eventArgs.controller, invite.from, "accept_invite")
            end
        }
    end

    local requests = friendslist.getrequests()
    for i = 1, requests.count do
        local req = requests[i]
        rows[#rows + 1] = {
            label = "^5+ DEMANDE D'AMI DE " .. ToUpperCase(req.name) .. " (cliquez pour accepter)",
            infoTitle = "Demande d'ami",
            infoDesc = req.name .. " veut vous ajouter. Cliquez pour accepter - vous serez amis des deux cotes.",
            onClick = function(element, eventArgs)
                Engine.Exec("friend_accept " .. req.name)
            end,
            forceRefresh = true
        }
    end

    -- ===== ACTIONS =====
    rows[#rows + 1] = {
        label = "^3>> CREER UNE PARTIE ENTRE AMIS",
        infoTitle = Engine.IsAliensMode() and "Creer une partie zombies" or "Creer une partie",
        infoDesc = "Ouvre le salon de partie. Au lancement: port ouvert (UPnP) et amis invites automatiquement.",
        onClick = function(element, eventArgs)
            if Engine.IsAliensMode() then
                Engine.Exec(MPConfig.default_xboxlive, eventArgs.controller)
                Engine.SetDvarBool("xblive_privatematch", true)
                SetIsAliensSolo(false)
                Engine.Exec("xstartprivatematch")
                LUI.FlowManager.RequestAddMenu("CPPrivateMatchMenu", false, eventArgs.controller, false, {
                    showPlayNowButton = true,
                    isPublicMatch = false
                })
            else
                OpenPrivateMatchLobby(eventArgs)
            end
        end
    }

    if friendslist.getmycode() ~= "" then
        rows[#rows + 1] = {
            label = "^7[ ] Copier mon code ami (a partager sur Discord)",
            infoTitle = "Mon code ami",
            infoDesc = "Copie ton code dans le presse-papiers. Colle-le a un pote (Discord...) pour qu'il t'ajoute.",
            onClick = function(element, eventArgs)
                Engine.Exec("invite_code")
            end
        }
    end

    -- ===== FRIENDS =====
    local friends = friendslist.getall()
    local onlineCount = 0
    for i = 1, friends.count do
        if friends[i].online then
            onlineCount = onlineCount + 1
        end
    end

    rows[#rows + 1] = {
        label = "^7------ MES AMIS (" .. onlineCount .. "/" .. friends.count .. " en ligne) ------",
        infoTitle = "Mes amis",
        infoDesc = "^2Vert^7 = en partie (cliquez pour rejoindre). ^3Jaune^7 = en ligne. ^1Rouge^7 = hors ligne."
    }

    if friends.count == 0 then
        rows[#rows + 1] = {
            label = "(aucun ami pour l'instant)",
            infoTitle = "Aucun ami",
            infoDesc = "Joue une partie avec quelqu'un et il sera ajoute automatiquement. Ou partage ton code."
        }
    end

    for i = 1, friends.count do
        local friendEntry = friends[i]
        if friendEntry.online and friendEntry.ingame then
            rows[#rows + 1] = {
                label = "^2[EN PARTIE] " .. friendEntry.name,
                infoTitle = friendEntry.name,
                friendName = friendEntry.name,
                infoDesc = (friendEntry.gametype ~= "" and friendEntry.gametype or "?") .. " sur " ..
                    (friendEntry.mapname ~= "" and friendEntry.mapname or "?") .. " (" .. friendEntry.clients .. "/" ..
                    friendEntry.maxclients .. ") - cliquez pour rejoindre !  ^7[Y] renommer  [X] supprimer",
                onClick = function(element, eventArgs)
                    confirmJoin(eventArgs.controller, friendEntry.name, "join " .. friendEntry.name)
                end
            }
        elseif friendEntry.online then
            rows[#rows + 1] = {
                label = "^3[EN LIGNE] " .. friendEntry.name,
                infoTitle = friendEntry.name,
                friendName = friendEntry.name,
                infoDesc = "Dans les menus. Creez une partie pour l'inviter.  ^7[Y] renommer  [X] supprimer",
                onClick = function(element, eventArgs)
                    confirmJoin(eventArgs.controller, friendEntry.name, "join " .. friendEntry.name)
                end
            }
        else
            rows[#rows + 1] = {
                label = "^1[HORS LIGNE] " .. friendEntry.name,
                infoTitle = friendEntry.name,
                friendName = friendEntry.name,
                infoDesc = "Injoignable pour le moment.  ^7[Y] renommer  [X] supprimer"
            }
        end
    end

    -- ===== RECENT PLAYERS =====
    local recent = friendslist.getrecent()
    if recent.count > 0 then
        rows[#rows + 1] = {
            label = "^7------ JOUEURS RECENTS ------",
            infoTitle = "Joueurs recents",
            infoDesc = "Les joueurs croises en partie. Cliquez sur un nom pour l'ajouter en ami."
        }

        for i = 1, recent.count do
            local recentEntry = recent[i]
            rows[#rows + 1] = {
                label = "^5[+] " .. recentEntry.name,
                infoTitle = recentEntry.name,
                infoDesc = "Cliquez pour ajouter " .. recentEntry.name .. " en ami.",
                onClick = function(element, eventArgs)
                    Engine.Exec("friend_add_recent " .. recentEntry.index)
                end,
                forceRefresh = true
            }
        end
    end

    return rows
end

local rowsSignature = function(rows)
    local signature = ""
    for i = 1, #rows do
        signature = signature .. rows[i].label .. "|"
    end
    return signature
end

local populateList = function(menuElement, controllerIndex)
    local rows = buildRows()
    menuElement.easyMPSignature = rowsSignature(rows)

    local dataSource = LUI.DataSourceFromList.new(#rows)
    dataSource.MakeDataSourceAtIndex = function(dataSource, index, controllerIndex)
        return {
            buttonLabel = LUI.DataSourceInGlobalModel.new(easyMPPath .. ".rows." .. index, rows[index + 1].label),
            buttonOnClickFunction = function(buttonElement, eventArgs)
                local row = rows[index + 1]
                if row.onClick then
                    Engine.PlaySound(CoD.SFX.SPMinimap)
                    row.onClick(buttonElement, eventArgs)
                    if row.forceRefresh then
                        menuElement.easyMPSignature = ""
                    end
                end
            end,
            buttonOnHoverFunction = function(buttonElement, eventArgs)
                onRowHover(buttonElement, controllerIndex, rows[index + 1])
            end,
        }
    end

    assert(menuElement.FriendsList)
    menuElement.FriendsList:SetGridDataSource(dataSource, controllerIndex)
end

local updateMyCode = function(menuElement)
    local myCode = friendslist.getmycode()
    if myCode ~= "" then
        menuElement.MyCodeText:setText("^3Mon code ami^7: " .. myCode .. "   (clique \"Copier mon code\" pour le partager)")
    else
        menuElement.MyCodeText:setText("^1Detection de l'IP publique en cours...")
    end
end

local function postLoadFunction(menuElement, controllerIndex, controller)
    assert(menuElement.bindButton)
    menuElement.bindButton:addEventHandler("button_secondary", leaveMenu)

    -- [X] supprimer l'ami survole (avec confirmation)
    menuElement.bindButton:addEventHandler("button_alt1", function(element, eventArgs)
        local name = menuElement.selectedFriend
        if not name then
            return
        end
        EasyMPConfirmData = {
            message = "Supprimer " .. name .. " de tes amis ?",
            title = "SUPPRIMER UN AMI",
            action = function()
                friendslist.remove(name)
                menuElement.easyMPSignature = ""
            end,
        }
        pcall(function()
            LUI.FlowManager.RequestPopupMenu(nil, "EasyMPConfirmPopup", true, eventArgs.controller, false)
        end)
    end)

    -- [Y] renommer l'ami survole (clavier a l'ecran)
    menuElement.bindButton:addEventHandler("button_alt2", function(element, eventArgs)
        local name = menuElement.selectedFriend
        if not name then
            return
        end
        local ctrl = eventArgs.controller or controllerIndex
        pcall(function()
            OSK.OpenScreenKeyboard(ctrl, Engine.Localize("Nouveau nom pour " .. name), name, 22, true, false, false,
                function(kbController, newName)
                    if newName and newName ~= "" then
                        friendslist.rename(name, newName)
                        menuElement.easyMPSignature = ""
                    end
                end)
        end)
    end)

    friendslist.refresh()
    populateList(menuElement, controllerIndex)
    updateMyCode(menuElement)

    -- refresh friend statuses while the menu is open;
    -- only rebuild the list when something actually changed to keep focus stable
    menuElement.easyMPAlive = true
    local stopPolling = function()
        menuElement.easyMPAlive = false
    end
    menuElement:addEventHandler("menu_close", stopPolling)
    menuElement:addEventHandler("menu_lose_focus", stopPolling)

    local pollFunction
    pollFunction = function()
        -- Stop the moment we leave this menu. Joining a game tears down the whole
        -- frontend without always firing menu_close, so also bail out if we are no
        -- longer in the frontend: touching destroyed UI elements crashes the LUI VM.
        if not menuElement.easyMPAlive or not Engine.InFrontend() then
            menuElement.easyMPAlive = false
            return
        end

        -- guard every UI access; if the element was freed under us, stop quietly
        local ok = pcall(function()
            friendslist.refresh()
            updateMyCode(menuElement)

            local rows = buildRows()
            if rowsSignature(rows) ~= menuElement.easyMPSignature then
                populateList(menuElement, controllerIndex)
            end
        end)

        if not ok or not menuElement.easyMPAlive then
            menuElement.easyMPAlive = false
            return
        end

        scheduler.once(pollFunction, 3000)
    end
    scheduler.once(pollFunction, 3000)

    menuElement:addEventHandler("gain_focus", function(focusElement, controllerIndex)
        local friendsList = focusElement.FriendsList

        if friendsList:getNumChildren() == 0 then
            return
        end

        local contentOffset = friendsList:GetContentOffset(LUI.DIRECTION.vertical)
        friendsList:SetFocusedPosition({
            x = 0,
            y = contentOffset
        }, true)
        local focusedElement = friendsList:GetElementAtPosition(0, contentOffset)
        if focusedElement then
            focusedElement:processEvent({
                name = "gain_focus",
                controllerIndex = controllerIndex
            })
        end
    end)
end

function EasyMPFriendsMenu(arg0, controller)
    local menuElement = LUI.UIElement.new()
    menuElement.id = "EasyMPFriendsMenu"

    local controllerIndex = controller and controller.controllerIndex
    if not controllerIndex and not Engine.InFrontend() then
        controllerIndex = menuElement:getRootController()
    end
    assert(controllerIndex)

    menuElement:playSound("menu_open")

    local buttonHelperBar = nil

    buttonHelperBar = MenuBuilder.BuildRegisteredType("ButtonHelperBar", {
        controllerIndex = controllerIndex
    })
    buttonHelperBar.id = "ButtonHelperBar"
    buttonHelperBar:SetAnchorsAndPosition(0, 0, 1, 0, 0, 0, _1080p * -85, 0)
    menuElement:addElement(buttonHelperBar)
    menuElement.ButtonHelperBar = buttonHelperBar

    local menuTitle = nil

    if Engine.IsAliensMode() then
        menuTitle = MenuBuilder.BuildRegisteredType("CPMenuTitle", {
            controllerIndex = controllerIndex
        })
    else
        menuTitle = MenuBuilder.BuildRegisteredType("MenuTitle", {
            controllerIndex = controllerIndex
        })
        menuTitle.MenuBreadcrumbs:setText(ToUpperCase(""), 0)
        menuTitle.Icon:SetTop(_1080p * -28.5, 0)
        menuTitle.Icon:SetBottom(_1080p * 61.5, 0)
    end
    menuTitle.id = "MenuTitle"
    menuTitle.MenuTitle:setText("JOUER ENTRE AMIS", 0)
    menuTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 96, _1080p * 1056, _1080p * 54, _1080p * 134)
    menuElement:addElement(menuTitle)
    menuElement.MenuTitle = menuTitle

    local infoTitle = nil

    infoTitle = LUI.UIStyledText.new()
    infoTitle.id = "InfoTitle"
    infoTitle:setText("", 0)
    infoTitle:SetFontSize(30 * _1080p)
    infoTitle:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
    infoTitle:SetAlignment(LUI.Alignment.Left)
    infoTitle:SetStartupDelay(2000)
    infoTitle:SetLineHoldTime(400)
    infoTitle:SetAnimMoveTime(300)
    infoTitle:SetEndDelay(1500)
    infoTitle:SetCrossfadeTime(750)
    infoTitle:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
    infoTitle:SetMaxVisibleLines(1)
    infoTitle:SetDecodeLetterLength(15)
    infoTitle:SetDecodeMaxRandChars(6)
    infoTitle:SetDecodeUpdatesPerLetter(4)
    infoTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 1254, _1080p * 1824, _1080p * 216, _1080p * 246)
    menuElement:addElement(infoTitle)
    menuElement.InfoTitle = infoTitle

    local infoText = nil

    infoText = LUI.UIStyledText.new()
    infoText.id = "InfoText"
    infoText:setText("", 0)
    infoText:SetFontSize(20 * _1080p)
    infoText:SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
    infoText:SetAlignment(LUI.Alignment.Left)
    infoText:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 1254, _1080p * 1824, _1080p * 248, _1080p * 328)
    menuElement:addElement(infoText)
    menuElement.InfoText = infoText

    local friendsList = nil

    friendsList = LUI.UIDataSourceGrid.new(nil, {
        maxVisibleColumns = 1,
        maxVisibleRows = 17,
        controllerIndex = controllerIndex,
        buildChild = function()
            return MenuBuilder.BuildRegisteredType("EasyMPFriendButton", {
                controllerIndex = controllerIndex
            })
        end,
        wrapX = true,
        wrapY = true,
        spacingX = _1080p * 10,
        spacingY = _1080p * 10,
        columnWidth = _1080p * 500,
        rowHeight = _1080p * 30,
        scrollingThresholdX = 1,
        scrollingThresholdY = 1,
        adjustSizeToContent = false,
        horizontalAlignment = LUI.Alignment.Left,
        verticalAlignment = LUI.Alignment.Top,
        springCoefficient = 600,
        maxVelocity = 5000
    })
    friendsList.id = "FriendsList"
    friendsList:setUseStencil(false)
    friendsList:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 130, _1080p * 630, _1080p * 216, _1080p * 886)
    menuElement:addElement(friendsList)
    menuElement.FriendsList = friendsList

    local arrowUp = nil

    arrowUp = MenuBuilder.BuildRegisteredType("ArrowUp", {
        controllerIndex = controllerIndex
    })
    arrowUp.id = "ArrowUp"
    arrowUp:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 452.5, _1080p * 472.5, _1080p * 887, _1080p * 927)
    menuElement:addElement(arrowUp)
    menuElement.ArrowUp = arrowUp

    local arrowDown = nil

    arrowDown = MenuBuilder.BuildRegisteredType("ArrowDown", {
        controllerIndex = controllerIndex
    })
    arrowDown.id = "ArrowDown"
    arrowDown:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 287.5, _1080p * 307.5, _1080p * 886, _1080p * 926)
    menuElement:addElement(arrowDown)
    menuElement.ArrowDown = arrowDown

    local listCount = nil

    listCount = LUI.UIText.new()
    listCount.id = "ListCount"
    listCount:setText("", 0)
    listCount:SetFontSize(24 * _1080p)
    listCount:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
    listCount:SetAlignment(LUI.Alignment.Center)
    listCount:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 307.5, _1080p * 452.5, _1080p * 894, _1080p * 918)
    menuElement:addElement(listCount)
    menuElement.ListCount = listCount

    local myCodeText = nil

    myCodeText = LUI.UIText.new()
    myCodeText.id = "MyCodeText"
    myCodeText:setText("", 0)
    myCodeText:SetFontSize(20 * _1080p)
    myCodeText:SetFont(FONTS.GetFont(FONTS.MainBold.File))
    myCodeText:SetAlignment(LUI.Alignment.Left)
    myCodeText:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 130, _1080p * 1000, _1080p * 942, _1080p * 966)
    menuElement:addElement(myCodeText)
    menuElement.MyCodeText = myCodeText

    friendsList:AddArrow(arrowUp)
    friendsList:AddArrow(arrowDown)
    friendsList:AddItemNumbers(listCount)

    menuElement.addButtonHelperFunction = function(arg0, arg1)
        arg0:AddButtonHelperText({
            helper_text = Engine.Localize("MENU_BACK"),
            button_ref = "button_secondary",
            side = "left",
            clickable = true
        })
        arg0:AddButtonHelperText({
            helper_text = "Renommer",
            button_ref = "button_alt2",
            side = "right",
            clickable = true
        })
        arg0:AddButtonHelperText({
            helper_text = "Supprimer",
            button_ref = "button_alt1",
            side = "right",
            clickable = true
        })
    end

    menuElement:addEventHandler("menu_create", menuElement.addButtonHelperFunction)

    local bindButton = LUI.UIBindButton.new()
    bindButton.id = "selfBindButton"
    menuElement:addElement(bindButton)
    menuElement.bindButton = bindButton

    postLoadFunction(menuElement, controllerIndex, controller)

    if Engine.InFrontend() then
        local Blur = LUI.UIElement.new({
            worldBlur = 5
        })
        Blur:setupWorldBlur()
        Blur.id = "blur"
        menuElement:addElement(Blur)
    end

    return menuElement
end

MenuBuilder.registerType("EasyMPFriendsMenu", EasyMPFriendsMenu)
LUI.FlowManager.RegisterStackPushBehaviour("EasyMPFriendsMenu", PushFunc)
LUI.FlowManager.RegisterStackPopBehaviour("EasyMPFriendsMenu", easyMPFriendsCleanup)
