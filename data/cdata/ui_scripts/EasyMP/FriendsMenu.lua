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
    updateInfoPanel(menuElement)
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
                Engine.Exec("accept_invite")
            end
        }
    end

    rows[#rows + 1] = {
        label = "^3>> CREER UNE PARTIE ENTRE AMIS",
        infoTitle = Engine.IsAliensMode() and "Creer une partie zombies" or "Creer une partie",
        infoDesc = "Ouvre le salon de partie. Au lancement: port ouvert (UPnP) et amis invites automatiquement.",
        onClick = function(element, eventArgs)
            if Engine.IsAliensMode() then
                -- same flow as the native zombies CUSTOM GAME button
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

    rows[#rows + 1] = {
        label = "^7--------- MES AMIS ---------",
        infoTitle = "Mes amis",
        infoDesc = "^2Vert^7 = en partie (cliquez pour rejoindre). ^3Jaune^7 = en ligne. ^1Rouge^7 = hors ligne."
    }

    local friends = friendslist.getall()
    if friends.count == 0 then
        rows[#rows + 1] = {
            label = "(aucun ami - ajoutez-en via les joueurs recents ou la console)",
            infoTitle = "Aucun ami",
            infoDesc = "Console: friend_add <nom> <code ou ip:port>. Votre code est en bas de l'ecran."
        }
    end

    for i = 1, friends.count do
        local friendEntry = friends[i]
        if friendEntry.online and friendEntry.ingame then
            rows[#rows + 1] = {
                label = "^2[EN PARTIE] " .. friendEntry.name,
                infoTitle = friendEntry.name,
                infoDesc = (friendEntry.gametype ~= "" and friendEntry.gametype or "?") .. " sur " ..
                    (friendEntry.mapname ~= "" and friendEntry.mapname or "?") .. " (" .. friendEntry.clients .. "/" ..
                    friendEntry.maxclients .. ") - cliquez pour rejoindre !",
                onClick = function(element, eventArgs)
                    Engine.Exec("join " .. friendEntry.name)
                end
            }
        elseif friendEntry.online then
            rows[#rows + 1] = {
                label = "^3[EN LIGNE] " .. friendEntry.name,
                infoTitle = friendEntry.name,
                infoDesc = "Dans les menus. Creez une partie pour l'inviter automatiquement.",
                onClick = function(element, eventArgs)
                    Engine.Exec("join " .. friendEntry.name)
                end
            }
        else
            rows[#rows + 1] = {
                label = "^1[HORS LIGNE] " .. friendEntry.name,
                infoTitle = friendEntry.name,
                infoDesc = "Injoignable pour le moment. Il doit lancer IW7-Mod pour apparaitre en ligne."
            }
        end
    end

    local recent = friendslist.getrecent()
    if recent.count > 0 then
        rows[#rows + 1] = {
            label = "^7---- JOUEURS RECENTS ----",
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
        menuElement.MyCodeText:setText("^3Mon code ami^7: " .. myCode .. "   (console: friend_add <nom> <code>)")
    else
        menuElement.MyCodeText:setText("^1Detection de l'IP publique en cours...")
    end
end

local function postLoadFunction(menuElement, controllerIndex, controller)
    assert(menuElement.bindButton)
    menuElement.bindButton:addEventHandler("button_secondary", leaveMenu)

    friendslist.refresh()
    populateList(menuElement, controllerIndex)
    updateMyCode(menuElement)

    -- refresh friend statuses while the menu is open;
    -- only rebuild the list when something actually changed to keep focus stable
    menuElement.easyMPAlive = true
    menuElement:addEventHandler("menu_close", function(closedElement, eventArgs)
        menuElement.easyMPAlive = false
    end)

    local pollFunction
    pollFunction = function()
        if not menuElement.easyMPAlive then
            return
        end

        friendslist.refresh()
        updateMyCode(menuElement)

        local rows = buildRows()
        if rowsSignature(rows) ~= menuElement.easyMPSignature then
            populateList(menuElement, controllerIndex)
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
